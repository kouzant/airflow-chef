from airflow.plugins_manager import AirflowPlugin

from hopsworks_plugin.hooks.hopsworks_hook import HopsworksHook
from hopsworks_plugin.operators.hopsworks_operator import HopsworksRunOperator

class HopsworksPlugin(AirflowPlugin):
    name = "hopsworks_plugin"
    hooks = [HopsworksHook]
    operators = [HopsworksRunOperator]
