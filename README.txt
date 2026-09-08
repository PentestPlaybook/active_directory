############################################################
# AD ENUMERATION TOOLKIT - README
# Folder: 16_Active_Directory_Introduction_and_Enumeration/0_Enumeration_Script
#
# Files here:
#   adenum.ps1    - menu-driven AD enumeration (run this on target)
#   roasting.txt  - Kerberoast + AS-REP command reference (run from Kali/target)
#   README.txt    - this file
############################################################


========================================================
QUICK START (on the target, after you have a foothold)
========================================================
# 1. Get the script onto the box (RDP drive redirect, SMB, or http).
#    Via RDP drive (\\tsclient), example:
copy \\tsclient\<redirected_path>\adenum.ps1 .

# 2. Load and run:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. .\adenum.ps1          # <-- dot-source: leading DOT + SPACE. NOT Import-Module.
Invoke-ADMenu

# 3. Pick numbers from the menu. Everything auto-saves to:
#    .\adenum_<domain>_<timestamp>\


========================================================
PREREQUISITE (why it "just works" on any domain)
========================================================
The script auto-discovers Domain / PDC / DN at runtime via
GetCurrentDomain() and ([adsi]'').  Nothing is hardcoded, so the
SAME file works on corp.com, medtech.com, whatever.

REQUIRED CONTEXT: you must be running as a DOMAIN user on a
DOMAIN-JOINED host. If the menu header shows a red
"[!] can't reach domain", you're in a workgroup/non-domain shell
- that's the prereq failing, not a script bug.


========================================================
MENU OPTIONS
========================================================
  1) All users                         -> users.txt
  2) All groups                        -> groups.txt
  3) All computers                     -> computers.txt
  4) Kerberoastable users (SPN set)    -> kerberoastable.txt   *** get creds
  5) AS-REP roastable (no preauth)     -> asrep_roastable.txt  *** get creds
  6) Privileged users (adminCount=1)   -> privileged_admincount.txt
  7) Members of a group (prompts)      -> group_members_<name>.txt
  8) Look up one user (prompts)        -> user_<name>.txt
  9) Trusted for delegation            -> trusted_for_delegation.txt
 10) Custom raw LDAP filter (prompts)  -> custom.txt
 11) All groups + members             -> groups_members.txt
  0) Exit

Notes:
- Option 7 puts whatever you type into (cn=<text>), so wildcards work:
  type  Development Department*  to match with a trailing wildcard.
- Option 10 auto-wraps a filter missing outer parens, e.g.
  &(objectCategory=group)(cn=Sales*)  becomes  (&(objectCategory=group)(cn=Sales*))
- Every result is timestamped and APPENDED, so re-running keeps history.


========================================================
RECOMMENDED WORKFLOW
========================================================
  1  -> all users (also becomes the -usersfile for AS-REP spraying)
 11  -> all groups + members (spot nested groups / who is where)
  7  -> drill a group, follow nesting (repeat, changing the name)
  4  -> Kerberoastable? -> roasting.txt (GetUserSPNs / Rubeus) -> hashcat -m 13100
  5  -> AS-REP roastable? -> roasting.txt (GetNPUsers / Rubeus) -> hashcat -m 18200
  6/9 -> privileged accounts + delegation (escalation leads)
 crack -> validate with nxc smb/winrm -> feed user back into 7/8 -> repeat


========================================================
GETTING THE HASHES (see roasting.txt for full commands)
========================================================
This script FINDS roastable accounts; it does NOT pull tickets.
Kerberoast:  impacket-GetUserSPNs (Kali, needs creds)  OR  Rubeus kerberoast (target)
AS-REP:      impacket-GetNPUsers  (Kali, no creds)      OR  Rubeus asreproast (target)
hashcat:     13100 = Kerberoast   |   18200 = AS-REP


========================================================
GOTCHAS
========================================================
- Dot-source (. .\adenum.ps1), do not Import-Module (file has functions + output).
- Clock skew > 5 min breaks Kerberos:  sudo ntpdate <DC_IP>
- Use the FQDN domain (corp.com), not the NetBIOS short name.
- Single-quote passwords with special chars on Kali.
- TEST ONCE on a lab box before exam day: run Invoke-ADMenu, pick a few
  options, confirm files land in the evidence folder. (Script is
  written-and-reviewed but was not run against a live DC.)
- Legality: pure .NET DirectoryServices, your own script - OSCP-safe.
  No PowerView, no automated exploitation.
############################################################
