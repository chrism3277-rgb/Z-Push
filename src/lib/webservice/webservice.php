<?php
/***********************************************
* File      :   webservice.php
* Project   :   Z-Push
* Descr     :   Provides an interface for administration
*               tasks over a webservice
*
* Created   :   29.12.2011
*
* Copyright 2007 - 2016 Zarafa Deutschland GmbH
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU Affero General Public License, version 3,
* as published by the Free Software Foundation.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU Affero General Public License for more details.
*
* You should have received a copy of the GNU Affero General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*
* Consult LICENSE file for details
************************************************/

class Webservice {
    private $server;

    /**
     * Handles a webservice command
     *
     * @param int       $commandCode
     *
     * @access public
     * @return boolean
     * @throws SoapFault
     */
    public function Handle($commandCode) {
        if (Request::GetDeviceType() !== "webservice" || Request::GetDeviceID() !== "webservice") {
            throw new FatalException("Invalid device id and type for webservice execution");
        }

        $user = (Request::GetImpersonatedUser()) ? Request::GetImpersonatedUser() : Request::GetGETUser();
        if ($user != Request::GetAuthUser()) {
            ZLog::Write(LOGLEVEL_INFO, sprintf("Webservice::HandleWebservice('%s'): user '%s' executing action for user '%s'", $commandCode, Request::GetAuthUser(), $user));
        }

        // Webservice commands act on the account named in the "User" GET parameter, which is not
        // bound to the authenticated user. The only intended authorization check is
        // Backend->Setup($user, true) below, but diff-based backends (IMAP, CalDAV, CardDAV and
        // the combined backend) inherit BackendDiff::Setup(), which returns true for every store
        // except "SYSTEM". Without this gate any authenticated mailbox user could list, wipe and
        // remove another user's devices. These backends have no HTTP admin role (admin tasks run
        // through the z-push-admin CLI), so the webservice is restricted to the caller's own
        // account. A backend that implements a genuine admin ACL in Setup() would relax this.
        if (strcasecmp((string) $user, (string) Request::GetAuthUser()) !== 0) {
            ZLog::Write(LOGLEVEL_WARN, sprintf("Webservice::HandleWebservice('%s'): user '%s' denied - may only act on its own account, requested '%s'", $commandCode, Request::GetAuthUser(), $user));
            throw new AuthenticationRequiredException(sprintf("Not enough privileges of '%s' to act for user '%s': Permission denied", Request::GetAuthUser(), $user));
        }

        // initialize non-wsdl soap server
        $this->server = new SoapServer(null, array('uri' => "http://z-push.org/webservice"));

        // the webservice command is handled by its class
        if ($commandCode == ZPush::COMMAND_WEBSERVICE_DEVICE) {
            // check if the authUser has admin permissions to get data on the GETUser's device
            if (ZPush::GetBackend()->Setup($user, true) == false) {
                throw new AuthenticationRequiredException(sprintf("Not enough privileges of '%s' to setup for user '%s': Permission denied", Request::GetAuthUser(), $user));
            }

            ZLog::Write(LOGLEVEL_DEBUG, sprintf("Webservice::HandleWebservice('%s'): executing WebserviceDevice service", $commandCode));
            $this->server->setClass("WebserviceDevice");
        }
        elseif ($commandCode == ZPush::COMMAND_WEBSERVICE_INFO) {
            ZLog::Write(LOGLEVEL_DEBUG, sprintf("Webservice::HandleWebservice('%s'): executing WebserviceInfo service", $commandCode));
            $this->server->setClass("WebserviceInfo");
        }
        elseif ($commandCode == ZPush::COMMAND_WEBSERVICE_USERS) {
            if (!defined("ALLOW_WEBSERVICE_USERS_ACCESS") || ALLOW_WEBSERVICE_USERS_ACCESS !== true) {
                throw new HTTPReturnCodeException("Access to the WebserviceUsers service is disabled in configuration. Enable setting ALLOW_WEBSERVICE_USERS_ACCESS", 403);
            }

            ZLog::Write(LOGLEVEL_DEBUG, sprintf("Webservice::HandleWebservice('%s'): executing WebserviceUsers service", $commandCode));

            if (ZPush::GetBackend()->Setup("SYSTEM", true) == false) {
                throw new AuthenticationRequiredException(sprintf("User '%s' has no admin privileges", Request::GetAuthUser()));
            }

            $this->server->setClass("WebserviceUsers");
        }

        $this->server->handle();

        ZLog::Write(LOGLEVEL_DEBUG, sprintf("Webservice::HandleWebservice('%s'): sucessfully sent %d bytes", $commandCode, ob_get_length()));
        return true;
    }
}
