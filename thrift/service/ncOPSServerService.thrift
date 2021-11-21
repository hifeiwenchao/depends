
include "../datatype/ncData.thrift"

namespace py ncOPSServerService


service OPSService{

    i32 init_client(1:ncData.ncClientInfo client_info);
}
