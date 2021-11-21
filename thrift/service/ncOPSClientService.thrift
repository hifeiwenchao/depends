
include "../datatype/ncData.thrift"

namespace py ncOPSClientService


service OPSClientService{

    void start_service(1:string service_name);
    void stop_service(1:string service_name);
    void restart_service(1:string service_name);

    void start_os();
    void shutdown_os();
    void restart_os();

    string monitor();
    string backup(1:i32 record_id 2:ncData.ncDBInfo db_info, 3:ncData.ncUserInfo user);
    list<ncData.ncSysPartitionInfo> get_sys_partitions();

}
