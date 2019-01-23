import os
import hashlib
import urlparse
import requests

from requests import exceptions as requests_exceptions
from requests.auth import AuthBase

from airflow.hooks.base_hook import BaseHook
from airflow.utils.log.logging_mixin import LoggingMixin
from airflow.exceptions import AirflowException
from airflow import configuration

AIRFLOW_HOME_ENV = "AIRFLOW_HOME"
JWT_FILE_SUFFIX = ".jwt"

RUN_JOB = ("POST", "hopsworks-api/api/project/{project_id}/jobs/{job_name}/executions?action=start")


class HopsworksHook(BaseHook, LoggingMixin):
    def __init__(self, hopsworks_conn_id='hopsworks_default', project_id=None, owner=None):
        self.hopsworks_conn_id = hopsworks_conn_id
        self.project_id = project_id
        self.owner = owner
        self.hopsworks_conn = self.get_connection(hopsworks_conn_id)
        self.log.info("> Constructing HopsworksHook with id: %s",  hopsworks_conn_id)
        self._get_airflow_home()

    def start_job(self, job_name):
        self.log.info("Starting job %s", job_name)
        method, endpoint = RUN_JOB
        jwt = self._parse_jwt_for_user()
        endpoint = endpoint.format(project_id=self.project_id, job_name=job_name)
        url = "http://{host}:{port}/{endpoint}".format(
            host = self._parse_host(self.hopsworks_conn.host),
            endpoint = endpoint,
            port = self.hopsworks_conn.port)
        authentication = AuthorizationToken(jwt)
        try:
            response = requests.post(url, auth=authentication)
            return response.json()['state']
        except requests_exceptions.RequestException as ex:
            #msg = "Response: {0}, Status code: {1}".format(ex.response.content, ex.response.status_code)
            #self.log.error(msg)
            self.log.error(ex)
            raise AirflowException(ex)

    def _do_api_call(self):
        pass
        
    def _parse_host(self, host):
        """
        Host should be in the form of hostname:port
        Remove protocol or any endpoints from the host
        """
        parsed_host = urlparse.urlparse(host).hostname
        if parsed_host:
            # Host contains protocol
            return parsed_host
        return host

    def _get_airflow_home(self):
        if AIRFLOW_HOME_ENV in os.environ:
            return os.environ[AIRFLOW_HOME_ENV]
        airflow_home = configuration.conf.get("core", "airflow_home")
        if not airflow_home:
            raise AirflowException("Airflow home is not set in configuration, nor in $AIRFLOW_HOME")
        return airflow_home

    def _generate_secret_dir(self):
        if not self.project_id:
            raise AirflowException("Hopsworks Project ID is not set")
        return hashlib.sha256(str(self.project_id)).hexdigest()

    def _parse_jwt_for_user(self):
        if not self.owner:
            raise AirflowException("Owner of the DAG is not specified")
        
        airflow_home = self._get_airflow_home()
        secret_dir = self._generate_secret_dir()
        filename = self.owner + JWT_FILE_SUFFIX
        jwt_token_file = os.path.join(airflow_home, secret_dir, filename)

        if not os.path.isfile(jwt_token_file):
            raise AirflowException('Could not read JWT file for user {}'.format(self.owner))
        with open(jwt_token_file, 'r') as fd:
            return fd.read().strip()

class AuthorizationToken(AuthBase):
    def __init__(self, token):
        self.token = token

    def __call__(self, request):
        request.headers['Authorization'] = "Bearer " + self.token
        return request
