
namespace py ncOPSStruct.ncData

struct ncClientInfo{
    1: string ip;
    2: string version;
    3: string remark;
    4: string uuid;
    5: i32 cpu_count;
    6: double mem_total;
}

struct ncDBInfo{
    1: string name;
    2: i32 db_type;
    3: string backup_dir;
    4: string db_user;
    5: string db_password;
    6: i32 instance_id;
    7: i32 port;
}

struct ncUserInfo{
    1: i32 uid;
    2: string username;
}

struct ncSysPartitionInfo{
    1: string mountpoint;
    2: i64 total_size;
    3: i64 used_size;
    4: i64 free_size;
    5: double usage_percent;
}