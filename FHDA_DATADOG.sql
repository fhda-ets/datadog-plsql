/**
 * Copyright (c) 2020, Foothill-De Anza Community College District
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation and/or
 * other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its contributors
 * may be used to endorse or promote products derived from this software without
 * specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

--
-- The following anonymous block is a set up routine to check for (and create if needed)
-- a key/value settings table so that no essential config parameters or secrets are
-- hard coded into the PL/SQL.
--
declare
    l_table_exists number(1) := 0;
begin
    dbms_output.enable(999999);
    
    -- Query USER_TABLES to see if the Datadog settings table exists
    dbms_output.put_line('[Install] Checking if DATADOG_SETTINGS table exists in schema ' || user);
    select count(*) into l_table_exists from user_tables where table_name = 'DATADOG_SETTINGS';
    
    -- If not, create the table
    if l_table_exists < 1 then
        dbms_output.put_line('[Install] Does not exist. Will create.');
        execute immediate '
        create table ' || user || '.datadog_settings (
            key varchar2(128) primary key,
            value varchar2(128) not null)';
    end if;
end;
/

--
-- FHDA_DATADOG Package Header
--
create or replace package fhda_datadog as

    function F_GetSetting(pi_key varchar2) return varchar2;
    procedure P_PostEvent(pi_title varchar2, pi_text varchar2, pi_alert_type varchar2 default 'info');
    
end fhda_datadog;
/

--
-- FHDA_DATADOG Package Body
--
create or replace package body fhda_datadog as

    --
    -- Function F_GetSetting
    -- Query the DATADOG_SETTINGS table by key.
    -- @param pi_key Name of the setting to query
    -- @returns If found, the setting value, or raises error if not found
    --
    function F_GetSetting(pi_key varchar2) return varchar2 as
        l_return_value datadog_settings.value%type := null;
    begin
        -- Query DATADOG_SETTINGS by key
        select value into l_return_value from datadog_settings where key = pi_key;
        
        -- Return value if found
        return l_return_value;
    exception
        when no_data_found then
            raise_application_error(-20000, 'Setting ''' || pi_key || ''' not found in DATADOG_SETTINGS. Does it exist?');
    end;
    
    --
    -- Procedure P_PostEvent
    -- Create an event in the Datadog event stream. See also https://docs.datadoghq.com/api/?lang=bash#events
    -- @param pi_title The event title
    -- @param pi_text Body text of the event
    -- @param pi_alert_type Defaults to 'info', but can be 'error', 'warning', 'info', 'success'
    --
    procedure P_PostEvent(pi_title varchar2, pi_text varchar2, pi_alert_type varchar2 default 'info') as
        http_req utl_http.req;
        http_res utl_http.resp;
        l_datadog_base_url datadog_settings.value%type;
        l_datadog_api_key datadog_settings.value%type;
        l_api_url_post_event varchar2(32) := '/api/v1/events';
    begin
        -- Fetch settings
        l_datadog_base_url := F_GetSetting('BASE_URL');
        l_datadog_api_key := F_GetSetting('API_KEY');
        
        -- Create up HTTP request
        http_req := utl_http.begin_request(
            l_datadog_base_url || l_api_url_post_event,
            'POST',
            'HTTP/1.1');
            
        -- Add headers
        utl_http.set_header(http_req, 'Content-Type', 'application/json');
        utl_http.set_header(http_req, 'DD-API-KEY', l_datadog_api_key);
        
        -- Write event payload as JSON
        utl_http.write_text(http_req, '
        {
            "title": "' || pi_title || '",
            "text": "' || pi_text || '",
            "alert_type": "' || pi_alert_type || '"
        }');
        
        -- Send request
        http_res := utl_http.get_response(http_req);
    end;  
    
    --
    -- TO-DO: Coming later... an additional procedure to post log events.
    --

end fhda_datadog;
/

--
-- Simple unit test for validation and debugging
--
begin
    fhda_datadog.P_PostEvent(
        'Test Event',
        'This is being sent from PL/SQL');
end;
/