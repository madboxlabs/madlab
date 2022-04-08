* kvm notes

- Adding maching into the network config live.

virsh net-update default add ip-dhcp-host "<host mac='52:54:00:ed:a4:70' name='dev-srv-0' ip='192.168.122.10' />" --live --config
virsh net-update default add ip-dhcp-host "<host mac='52:54:00:d4:60:2a' name='dev-srv-1' ip='192.168.122.11' />" --live --config
virsh net-update default add ip-dhcp-host "<host mac='52:54:00:25:e8:0b' name='prd-srv-1' ip='192.168.122.12' />" --live --config
virsh net-update default add ip-dhcp-host "<host mac='52:54:00:4a:b1:9f' name='prd-srv-2' ip='192.168.122.13' />" --live --config
virsh net-update default add ip-dhcp-host "<host mac='52:54:00:a8:b3:83' name='qat-srv-1' ip='192.168.122.14' />" --live --config
virsh net-update default add ip-dhcp-host "<host mac='52:54:00:c4:9d:fb' name='qat-srv-2' ip='192.168.122.15' />" --live --config

virsh net-update default add ip-dhcp-host "<host mac='52:54:00:65:13:42' name='suma' ip='192.168.122.237' />" --live --config

virsh net-update default add ip-dhcp-host "<host mac='52:54:00:92:71:96' name='mbvm7' ip='192.168.122.17' />" --live --config
virsh net-update default add ip-dhcp-host "<host mac='52:54:00:f4:dc:07' name='mbvm8' ip='192.168.122.18' />" --live --config
virsh net-update default add ip-dhcp-host "<host mac='52:54:00:a6:76:43' name='mbvm9' ip='192.168.122.19' />" --live --config
