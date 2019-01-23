from airflow.models import BaseOperator
from airflow.utils.decorators import apply_defaults

from hopsworks_plugin.hooks.hopsworks_hook import HopsworksHook

class HopsworksRunOperator(BaseOperator):

    @apply_defaults
    def __init__(
            self,
            hopsworks_conn_id = 'hopsworks_default',
            job_name = None,
            project_id = None,
            **kwargs):
        super(HopsworksRunOperator, self).__init__(**kwargs)
        self.hopsworks_conn_id = hopsworks_conn_id
        self.job_name = job_name
        self.project_id = project_id

    def _get_hook(self):
        self.log.info("> Getting Hopsworks hook")
        return HopsworksHook(self.hopsworks_conn_id, self.project_id, self.owner)

    def execute(self, context):
        hook = self._get_hook()
        self.log.info("> Starting job %s", self.job_name)
        hook.start_job(self.job_name)
