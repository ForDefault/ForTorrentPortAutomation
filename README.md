# ForTorrentPortAutomation
-- qBitorrent .conf file requires sudo to be altered


>## Automates the following:

>### Fixes PrivateInternetAccess connections

-- Fixes the problem I often have when a remote connection exists but does not show current IP.
>### Updates forwarded port for qBitorrent

-- Checks the current PrivateInternetAccess port and compares with your current qBitorrent port.
-- If they differ, the qBitorrent port is upated to match the PrivateInternetAccess port.
>### UFW port changes

--Finds old port used by qBitorrent. Checks UFW. Deletes old port if different and adds new port 
-- **Currently the removal of the old port is not working. The adding of a new port does work**

#### *MANDATORY* you have to manually uncomment 3 values.
```
config_file=
kill_qbit=
launch_qbit=
```
### Are you using, flatpak or not, with qBitorrent? That is why the manual uncommenting is there and very obvious.

-- Currently, I have not got the removal of the "old_port" from the UFW  
