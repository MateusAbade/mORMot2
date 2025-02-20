/// Simple Network LDAP Client
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.net.ldap;

{
  *****************************************************************************

   Simple LDAP Protocol Client
    - LDAP Response Storage
    - LDAP Client Class

  *****************************************************************************
  Code below was inspired by Synapse Library code:
   The Initial Developer of the Original Code is Lukas Gebauer (Czech Republic).
   Portions created by Lukas Gebauer are (c)2003-2014. All Rights Reserved.
}

interface

{$I ..\mormot.defines.inc}

uses
  sysutils,
  classes,
  mormot.net.sock,
  mormot.core.base,
  mormot.core.os,
  mormot.core.buffers,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.data,
  mormot.crypt.core;


{ **************** LDAP Response Storage }

const
  GUID_COMPUTERS_CONTAINER_W                 = 'AA312825768811D1ADED00C04FD8D5CD';
  GUID_DELETED_OBJECTS_CONTAINER_W           = '18E2EA80684F11D2B9AA00C04F79F805';
  GUID_DOMAIN_CONTROLLERS_CONTAINER_W        = 'A361B2FFFFD211D1AA4B00C04FD7D83A';
  GUID_FOREIGNSECURITYPRINCIPALS_CONTAINER_W = '22B70C67D56E4EFB91E9300FCA3DC1AA';
  GUID_INFRASTRUCTURE_CONTAINER_W            = '2FBAC1870ADE11D297C400C04FD8D5CD';
  GUID_LOSTANDFOUND_CONTAINER_W              = 'AB8153B7768811D1ADED00C04FD8D5CD';
  GUID_MICROSOFT_PROGRAM_DATA_CONTAINER_W    = 'F4BE92A4C777485E878E9421D53087DB';
  GUID_NTDS_QUOTAS_CONTAINER_W               = '6227F0AF1FC2410D8E3BB10615BB5B0F';
  GUID_PROGRAM_DATA_CONTAINER_W              = '09460C08AE1E4A4EA0F64AEE7DAA1E5A';
  GUID_SYSTEMS_CONTAINER_W                   = 'AB1D30F3768811D1ADED00C04FD8D5CD';
  GUID_USERS_CONTAINER_W                     = 'A9D1CA15768811D1ADED00C04FD8D5CD';
  GUID_MANAGED_SERVICE_ACCOUNTS_CONTAINER_W  = '1EB93889E40C45DF9F0C64D23BBB6237';

type
  /// store a named LDAP attribute with the list of its values
  TLdapAttribute = class
  private
    fList: TRawUtf8DynArray;
    fAttributeName: RawUtf8;
    fCount: integer;
    fIsBinary: boolean;
  public
    /// initialize the attribute(s) storage
    constructor Create(const AttrName: RawUtf8);
    /// include a new value to this list
    // - IsBinary values will be stored base-64 encoded
    procedure Add(const aValue: RawByteString);
    /// retrieve a value as human-readable text
    function GetReadable(index: PtrInt = 0): RawUtf8;
    /// retrieve a value as its inital value stored with Add()
    function GetRaw(index: PtrInt = 0): RawByteString;
    /// how many values have been added to this attribute
    property Count: integer
      read fCount;
    /// name of this LDAP attribute
    property AttributeName: RawUtf8
      read fAttributeName;
    /// true if the attribute contains binary data
    property IsBinary: boolean
      read fIsBinary;
  end;
  /// dynamic array of LDAP attribute, as stored in TLdapAttributeList
  TLdapAttributeDynArray = array of TLdapAttribute;

  /// list one or several TLdapAttribute
  TLdapAttributeList = class
  private
    fItems: TLdapAttributeDynArray;
  public
    /// finalize the list
    destructor Destroy; override;
    /// clear the list
    procedure Clear;
    /// number of TLdapAttribute objects in this list
    function Count: integer;
      {$ifdef HASINLINE} inline; {$endif}
    /// allocate and a new TLdapAttribute object and its value to the list
    function Add(const AttributeName: RawUtf8;
      const AttributeValue: RawByteString): TLdapAttribute; overload;
    /// allocate and a new TLdapAttribute object to the list
    function Add(const AttributeName: RawUtf8): TLdapAttribute; overload;
    /// remove one TLdapAttribute object from the list
    procedure Delete(const AttributeName: RawUtf8);
    /// find and return attribute index with the requested name
    // - returns -1 if not found
    function FindIndex(const AttributeName: RawUtf8): PtrInt;
    /// find and return attribute with the requested name
    // - returns nil if not found
    function Find(const AttributeName: RawUtf8): TLdapAttribute;
    /// Find and return first attribute value with requested name
    // - calls GetReadable(0) on the found attribute
    // - returns empty string if not found
    function Get(const AttributeName: RawUtf8): RawUtf8;
    /// access to the internal list of TLdapAttribute objects
    property Items: TLdapAttributeDynArray
      read fItems;
  end;

  /// store one LDAP result, i.e. object name and attributes
  TLdapResult = class
  private
    fObjectName: RawUtf8;
    fAttributes: TLdapAttributeList;
  public
    /// initialize the instance
    constructor Create; reintroduce;
    /// finalize the instance
    destructor Destroy; override;
    /// Name of this LDAP object
    property ObjectName: RawUtf8
      read fObjectName write fObjectName;
    /// Here is list of object attributes
    property Attributes: TLdapAttributeList read fAttributes;
    /// Copy the 'objectSid' attribute if present
    // - Return true on success
    function CopyObjectSid(out objectSid: TSid): boolean;
    /// Copy the 'objectGUID' attribute if present
    // - Return true on success
    function CopyObjectGUID(out objectGUID: TGuid): boolean;
  end;
  TLdapResultObjArray = array of TLdapResult;

  /// maintain a list of LDAP result objects
  TLdapResultList = class(TObject)
  private
    fItems: TLdapResultObjArray;
    fCount: integer;
  public
    /// finalize the list
    destructor Destroy; override;
    /// create and add new TLdapResult object to the list
    function Add: TLdapResult;
    /// clear all TLdapResult objects in list
    procedure Clear;
    /// dump the result of a LDAP search into human readable form
    // - used for debugging
    function Dump: RawUtf8;
    /// number of TLdapResult objects in list
    property Count: integer
      read fCount;
    /// List of TLdapResult objects
    property Items: TLdapResultObjArray
      read fItems;
  end;


/// convert a Distinguished Name to a Canonical Name
// - raise an exception if the supplied DN is not a valid Distinguished Name
// - e.g. DNToCN('CN=User1,OU=Users,OU=London,DC=xyz,DC=local') =
// 'xyz.local/london/users/user1'
function DNToCN(const DN: RawUtf8): RawUtf8;


{ **************** LDAP Client Class }

type
  /// define possible operations for LDAP MODIFY operations
  TLdapModifyOp = (
    MO_Add,
    MO_Delete,
    MO_Replace
  );

  /// define possible values for LDAP search scope
  TLdapSearchScope = (
    SS_BaseObject,
    SS_SingleLevel,
    SS_WholeSubtree
  );

  /// define possible values about LDAP alias dereferencing
  TLdapSearchAliases = (
    SA_NeverDeref,
    SA_InSearching,
    SA_FindingBaseObj,
    SA_Always
  );

  /// we defined our own type to hold an ASN object binary
  TAsnObject = RawByteString;

  /// implementation of LDAP client version 2 and 3
  // - Authentication use Username/Password properties
  // - Server/Port use TargetHost/TargetPort properties
  TLdapClient = class(TSynPersistent)
  private
    fTargetHost: RawUtf8;
    fTargetPort: RawUtf8;
    fTimeout: integer;
    fUserName: RawUtf8;
    fPassword: RawUtf8;
    fSock: TCrtSocket;
    fResultCode: integer;
    fResultString: RawUtf8;
    fFullResult: TAsnObject;
    fFullTls: boolean;
    fTlsContext: PNetTlsContext;
    fSeq: integer;
    fResponseCode: integer;
    fResponseDN: RawUtf8;
    fReferals: TRawUtf8List;
    fVersion: integer;
    fSearchScope: TLdapSearchScope;
    fSearchAliases: TLdapSearchAliases;
    fSearchSizeLimit: integer;
    fSearchTimeLimit: integer;
    fSearchPageSize: integer;
    fSearchCookie: RawUtf8;
    fSearchResult: TLdapResultList;
    fExtName: RawUtf8;
    fExtValue: RawUtf8;
    fRootDN: RawUtf8;
    fBound: boolean;
    function Connect: boolean;
    function BuildPacket(const Asn1Data: TAsnObject): TAsnObject;
    function GetRootDN: RawUtf8;
    procedure SendPacket(const Asn1Data: TAsnObject);
    function ReceiveResponse: TAsnObject;
    function DecodeResponse(const Asn1Response: TAsnObject): TAsnObject;
    function SendAndReceive(const Asn1Data: TAsnObject): TAsnObject;
    function SaslDigestMd5(const Value: RawUtf8): RawUtf8;
    function TranslateFilter(const Filter: RawUtf8): TAsnObject;
    class function GetErrorString(ErrorCode: integer): RawUtf8;
    function ReceiveString(Size: integer): RawByteString;
  public
    /// initialize this LDAP client instance
    constructor Create; override;
    /// finalize this LDAP client instance
    destructor Destroy; override;
    /// try to connect to LDAP server and start secure channel when it is required
    function Login: boolean;
    /// authenticate a client to the directory server with Username/Password
    // - if this is empty strings, then it does annonymous binding
    // - when you not call Bind on LDAPv3, then anonymous mode is used
    // - warning: uses plaintext transport of password - consider using TLS
    function Bind: boolean;
    /// authenticate a client to the directory server with Username/Password
    // - when you not call Bind on LDAPv3, then anonymous mode is used
    // - uses DIGEST-MD5 as password obfuscation challenge - consider using TLS
    function BindSaslDigestMd5: boolean;
    /// close connection to the LDAP server
    function Logout: boolean;
    /// retrieve all entries that match a given set of criteria
    // - will generate as many requests/responses as needed to retrieve all
    // the information into the SearchResult property
    function Search(const BaseDN: RawUtf8; TypesOnly: boolean;
      Filter: RawUtf8; const Attributes: array of RawByteString): boolean;
    /// retrieve all entries that match a given set of criteria and return the
    // first result
    // - Will call Search method, therefore SearchResult will contains all the results
    // - Returns nil if no result is found or if the search failed
    function SearchFirst(const BaseDN: RawUtf8; Filter: RawUtf8;
      const Attributes: array of RawByteString): TLdapResult;
    /// retrieve the entry matching the given ObjectDN
    // - Will call Search method, therefore SearchResult will contains all the results
    // - Returns nil if the object is not found or if the search failed
    function SearchObject(const ObjectDN: RawUtf8; const Attributes: array of RawByteString): TLdapResult;
    /// create a new entry in the directory
    function Add(const Obj: RawUtf8; Value: TLdapAttributeList): boolean;
    /// Add a new computer in the domain
    // - If password is empty, it isn't set in the attributes
    // - If DeleteIfPresent is false and there is already a computer with this
    // name in the domain, the operation fail
    // - ErrorMessage contains the failure reason (if the operation failed)
    // - Return false if the operation failed
    function AddComputer(const ComputerParentDN, ComputerName: RawUtf8;
      out ErrorMessage: RawUtf8; const Password: SpiUtf8 = '';
      DeleteIfPresent : boolean = false): boolean;
    /// make one or more changes to the set of attribute values in an entry
    function Modify(const Obj: RawUtf8; Op: TLdapModifyOp;
      Value: TLdapAttribute): boolean;
    /// change an entry’s DN
    // - it can be used to rename the entry (by changing its RDN), move it to a
    // different location in the DIT (by specifying a new parent entry), or both
    function ModifyDN(const obj, newRdn, newSuperior: RawUtf8;
      DeleteOldRdn: boolean): boolean;
    ///  remove an entry from the directory server
    function Delete(const Obj: RawUtf8): boolean;
    /// determine whether a given entry has a specified attribute value
    function Compare(const Obj, AttributeValue: RawUtf8): boolean;
    /// call any LDAP v3 extended operations
    // - e.g. StartTLS, cancel, transactions
    function Extended(const Oid, Value: RawUtf8): boolean;
    /// try to discover the root DN of the AD
    // - Return an empty string if not found
    function DiscoverRootDN: RawUtf8;
    /// test whether the client is connected to the server
    // - if AndBound is set, it also checks that a successfull bind request has been made
    function Connected(AndBound: boolean = true): boolean;
    /// try to retrieve a well known object DN from its GUID
    // - see GUID_*_W constants, e.g. GUID_COMPUTERS_CONTAINER_W
    // - search in object identified by the RootDN property
    // - return an empty string if not found
    function GetWellKnownObjectDN(const ObjectGUID: RawUtf8): RawUtf8;
    /// the version of LDAP protocol used
    // - default value is 3
    property Version: integer
      read fVersion Write fVersion;
    /// target server IP (or symbolic name)
    // - default is 'localhost'
    property TargetHost: RawUtf8
      read fTargetHost Write fTargetHost;
    /// target server port (or symbolic name)
    // - is '389' by default but should be '636' (or '3269') on TLS
    property TargetPort: RawUtf8
      read fTargetPort Write fTargetPort;
    /// milliseconds timeout for socket operations
    // - default is 5000, ie. 5 seconds
    property Timeout: integer
      read fTimeout Write fTimeout;
    /// if protocol needs user authorization, then fill here user name
    property UserName: RawUtf8
      read fUserName Write fUserName;
    /// if protocol needs user authorization, then fill here its password
    property Password: RawUtf8
      read fPassword Write fPassword;
    /// contains the result code of the last LDAP operation
    // - could be e.g. LDAP_RES_SUCCESS or an error code - see ResultString
    property ResultCode: integer
      read fResultCode;
    /// human readable description of the last LDAP operation
    property ResultString: RawUtf8
      read fResultString;
    /// binary string of the last full response from LDAP server
    // - This string is encoded by ASN.1 BER encoding
    // - You need this only for debugging
    property FullResult: TAsnObject
      read fFullResult;
    /// if connection to the LDAP server is through TLS tunnel
    property FullTls: boolean
      read fFullTls Write fFullTls;
    /// optional advanced options for FullTls = true
    property TlsContext: PNetTlsContext
      read fTlsContext write fTlsContext;
    /// sequence number of the last LDAP command
    // - incremented with any LDAP command
    property Seq: integer
      read fSeq;
    /// the search scope used in search command
    property SearchScope: TLdapSearchScope
      read fSearchScope Write fSearchScope;
    /// how to handle aliases in search command
    property SearchAliases: TLdapSearchAliases
      read fSearchAliases Write fSearchAliases;
    /// result size limit in search command (bytes)
    // - 0 means without size limit
    property SearchSizeLimit: integer
      read fSearchSizeLimit Write fSearchSizeLimit;
    /// search time limit in search command (seconds)
    // - 0 means without time limit
    property SearchTimeLimit: integer
      read fSearchTimeLimit Write fSearchTimeLimit;
    /// number of results to return per search request
    // - 0 means no paging
    property SearchPageSize: integer
      read fSearchPageSize Write fSearchPageSize;
    /// cookie returned by paged search results
    // - use an empty string for the first search request
    property SearchCookie: RawUtf8
      read fSearchCookie Write fSearchCookie;
    /// result of the search command
    property SearchResult: TLdapResultList read fSearchResult;
    /// each LDAP operation on server can return some referals URLs
    property Referals: TRawUtf8List
      read fReferals;
    /// on Extended operation, here is the result Name asreturned by server
    property ExtName: RawUtf8
      read fExtName;
    /// on Extended operation, here is the result Value as returned by server
    property ExtValue: RawUtf8 read
      fExtValue;
    /// raw TCP socket used by all LDAP operations
    property Sock: TCrtSocket
      read fSock;
    /// Root DN, retrieved using DiscoverRootDN if possible
    property RootDN: RawUtf8
      read GetRootDN Write fRootDN;
  end;

const
  LDAP_RES_SUCCESS                        = 0;
  LDAP_RES_OPERATIONS_ERROR               = 1;
  LDAP_RES_PROTOCOL_ERROR                 = 2;
  LDAP_RES_TIME_LIMIT_EXCEEDED            = 3;
  LDAP_RES_SIZE_LIMIT_EXCEEDED            = 4;
  LDAP_RES_COMPARE_FALSE                  = 5;
  LDAP_RES_COMPARE_TRUE                   = 6;
  LDAP_RES_AUTH_METHOD_NOT_SUPPORTED      = 7;
  LDAP_RES_STRONGER_AUTH_REQUIRED         = 8;
  LDAP_RES_REFERRAL                       = 10;
  LDAP_RES_ADMIN_LIMIT_EXCEEDED           = 11;
  LDAP_RES_UNAVAILABLE_CRITICAL_EXTENSION = 12;
  LDAP_RES_CONFIDENTIALITY_REQUIRED       = 13;
  LDAP_RES_SASL_BIND_IN_PROGRESS          = 14;
  LDAP_RES_NO_SUCH_ATTRIBUTE              = 16;
  LDAP_RES_UNDEFINED_ATTRIBUTE_TYPE       = 17;
  LDAP_RES_INAPPROPRIATE_MATCHING         = 18;
  LDAP_RES_CONSTRAINT_VIOLATION           = 19;
  LDAP_RES_ATTRIBUTE_OR_VALUE_EXISTS      = 20;
  LDAP_RES_INVALID_ATTRIBUTE_SYNTAX       = 21;
  LDAP_RES_NO_SUCH_OBJECT                 = 32;
  LDAP_RES_ALIAS_PROBLEM                  = 33;
  LDAP_RES_INVALID_DN_SYNTAX              = 34;
  LDAP_RES_IS_LEAF                        = 35;
  LDAP_RES_ALIAS_DEREFERENCING_PROBLEM    = 36;
  LDAP_RES_INAPPROPRIATE_AUTHENTICATION   = 48;
  LDAP_RES_INVALID_CREDENTIALS            = 49;
  LDAP_RES_INSUFFICIENT_ACCESS_RIGHTS     = 50;
  LDAP_RES_BUSY                           = 51;
  LDAP_RES_UNAVAILABLE                    = 52;
  LDAP_RES_UNWILLING_TO_PERFORM           = 53;
  LDAP_RES_LOOP_DETECT                    = 54;
  LDAP_RES_SORT_CONTROL_MISSING           = 60;
  LDAP_RES_OFFSET_RANGE_ERROR             = 61;
  LDAP_RES_NAMING_VIOLATION               = 64;
  LDAP_RES_OBJECT_CLASS_VIOLATION         = 65;
  LDAP_RES_NOT_ALLOWED_ON_NON_LEAF        = 66;
  LDAP_RES_NOT_ALLOWED_ON_RDN             = 67;
  LDAP_RES_ENTRY_ALREADY_EXISTS           = 68;
  LDAP_RES_OBJECT_CLASS_MODS_PROHIBITED   = 69;
  LDAP_RES_RESULTS_TOO_LARGE              = 70;
  LDAP_RES_AFFECTS_MULTIPLE_DSAS          = 71;
  LDAP_RES_CONTROL_ERROR                  = 76;
  LDAP_RES_OTHER                          = 80;
  LDAP_RES_SERVER_DOWN                    = 81;
  LDAP_RES_LOCAL_ERROR                    = 82;
  LDAP_RES_ENCODING_ERROR                 = 83;
  LDAP_RES_DECODING_ERROR                 = 84;
  LDAP_RES_TIMEOUT                        = 85;
  LDAP_RES_AUTH_UNKNOWN                   = 86;
  LDAP_RES_FILTER_ERROR                   = 87;
  LDAP_RES_USER_CANCELED                  = 88;
  LDAP_RES_PARAM_ERROR                    = 89;
  LDAP_RES_NO_MEMORY                      = 90;
  LDAP_RES_CONNECT_ERROR                  = 91;
  LDAP_RES_NOT_SUPPORTED                  = 92;
  LDAP_RES_CONTROL_NOT_FOUND              = 93;
  LDAP_RES_NO_RESULTS_RETURNED            = 94;
  LDAP_RES_MORE_RESULTS_TO_RETURN         = 95;
  LDAP_RES_CLIENT_LOOP                    = 96;
  LDAP_RES_REFERRAL_LIMIT_EXCEEDED        = 97;
  LDAP_RES_INVALID_RESPONSE               = 100;
  LDAP_RES_AMBIGUOUS_RESPONSE             = 101;
  LDAP_RES_TLS_NOT_SUPPORTED              = 112;
  LDAP_RES_INTERMEDIATE_RESPONSE          = 113;
  LDAP_RES_UNKNOWN_TYPE                   = 114;
  LDAP_RES_CANCELED                       = 118;
  LDAP_RES_NO_SUCH_OPERATION              = 119;
  LDAP_RES_TOO_LATE                       = 120;
  LDAP_RES_CANNOT_CANCEL                  = 121;
  LDAP_RES_ASSERTION_FAILED               = 122;
  LDAP_RES_AUTHORIZATION_DENIED           = 123;
  LDAP_RES_ESYNC_REFRESH_REQUIRED         = 4096;
  LDAP_RES_NO_OPERATION                   = 16654;



implementation


{ ****** Support procedures and functions ****** }

procedure UnquoteStr(Value: PUtf8Char; var result: RawUtf8);
begin
  if (Value = nil) or
     (Value^ <> '"') then
    FastSetString(result, Value, StrLen(Value))
  else
    UnQuoteSqlStringVar(Value, result);
end;

function IsBinaryString(const Value: RawByteString): boolean;
var
  n: PtrInt;
begin
  result := true;
  for n := 1 to length(Value) do
    if ord(Value[n]) in [0..8, 10..31] then
      // consider null-terminated strings as non-binary
      if (n <> length(value)) or
         (Value[n] = #0) then
        exit;
  result := false;
end;

function SeparateLeft(const Value: RawUtf8; Delimiter: AnsiChar): RawUtf8;
var
  x: PtrInt;
begin
  x := PosExChar(Delimiter, Value);
  if x = 0 then
    result := Value
  else
    result := copy(Value, 1, x - 1);
end;

function SeparateRight(const Value: RawUtf8; Delimiter: AnsiChar): RawUtf8;
var
  x: PtrInt;
begin
  x := PosExChar(Delimiter, Value);
  result := copy(Value, x + 1, length(Value) - x);
end;

function SeparateRightU(const Value, Delimiter: RawUtf8): RawUtf8;
var
  x: PtrInt;
begin
  x := mormot.core.base.PosEx(Delimiter, Value);
  TrimCopy(Value, x + 1, length(Value) - x, result);
end;

function GetBetween(PairBegin, PairEnd: AnsiChar; const Value: RawUtf8): RawUtf8;
var
  n, len, x: PtrInt;
  s: RawUtf8;
begin
  n := length(Value);
  if (n = 2) and
     (Value[1] = PairBegin) and
     (Value[2] = PairEnd) then
  begin
    result := '';//nothing between
    exit;
  end;
  if n < 2 then
  begin
    result := Value;
    exit;
  end;
  s := SeparateRight(Value, PairBegin);
  if s = Value then
  begin
    result := Value;
    exit;
  end;
  n := PosExChar(PairEnd, s);
  if n = 0 then
  begin
    result := Value;
    exit;
  end;
  len := length(s);
  x := 1;
  for n := 1 to len do
  begin
    if s[n] = PairBegin then
      inc(x)
    else if s[n] = PairEnd then
    begin
      dec(x);
      if x <= 0 then
      begin
        len := n - 1;
        break;
      end;
    end;
  end;
  result := copy(s, 1, len);
end;

function DecodeTriplet(const Value: RawUtf8; Delimiter: AnsiChar): RawUtf8;
var
  x, l, lv: integer;
  c: AnsiChar;
  b: byte;
  bad: boolean;
begin
  lv := length(Value);
  SetLength(result, lv);
  x := 1;
  l := 1;
  while x <= lv do
  begin
    c := Value[x];
    inc(x);
    if c <> Delimiter then
    begin
      result[l] := c;
      inc(l);
    end
    else
      if x < lv then
      begin
        case Value[x] of
          #13:
            if Value[x + 1] = #10 then
              inc(x, 2)
            else
              inc(x);
          #10:
            if Value[x + 1] = #13 then
              inc(x, 2)
            else
              inc(x);
        else
          begin
            bad := false;
            case Value[x] of
              '0'..'9':
                b := (byte(Value[x]) - 48) shl 4;
              'a'..'f', 'A'..'F':
                b := ((byte(Value[x]) and 7) + 9) shl 4;
            else
              begin
                b := 0;
                bad := true;
              end;
            end;
            case Value[x + 1] of
              '0'..'9':
                b := b or (byte(Value[x + 1]) - 48);
              'a'..'f', 'A'..'F':
                b := b or ((byte(Value[x + 1]) and 7) + 9);
            else
              bad := true;
            end;
            if bad then
            begin
              result[l] := c;
              inc(l);
            end
            else
            begin
              inc(x, 2);
              result[l] := AnsiChar(b);
              inc(l);
            end;
          end;
        end;
      end
      else
        break;
  end;
  dec(l);
  SetLength(result, l);
end;

function TrimSPLeft(const S: RawUtf8): RawUtf8;
var
  i, l: integer;
begin
  result := '';
  if S = '' then
    exit;
  l := length(S);
  i := 1;
  while (i <= l) and
        (S[i] = ' ') do
    inc(i);
  result := copy(S, i, Maxint);
end;

function TrimSPRight(const S: RawUtf8): RawUtf8;
var
  i: integer;
begin
  result := '';
  if S = '' then
    exit;
  i := length(S);
  while (i > 0) and
        (S[i] = ' ') do
    dec(i);
  result := copy(S, 1, i);
end;

function TrimSP(const S: RawUtf8): RawUtf8;
begin
  result := TrimSPRight(TrimSPLeft(s));
end;

function FetchBin(var Value: RawUtf8; Delimiter: AnsiChar): RawUtf8;
var
  s: RawUtf8;
begin
  result := SeparateLeft(Value, Delimiter);
  s := SeparateRight(Value, Delimiter);
  if s = Value then
    Value := ''
  else
    Value := s;
end;

function Fetch(var Value: RawUtf8; Delimiter: AnsiChar): RawUtf8;
begin
  result := TrimSP(FetchBin(Value, Delimiter));
  Value := TrimSP(Value);
end;



{ ****** ASN.1 BER encoding/decoding ****** }

const
  // base types
  ASN1_BOOL        = $01;
  ASN1_INT         = $02;
  ASN1_BITSTR      = $03;
  ASN1_OCTSTR      = $04;
  ASN1_NULL        = $05;
  ASN1_OBJID       = $06;
  ASN1_ENUM        = $0a;
  ASN1_UTF8STRING  = $0c;
  ASN1_SEQ         = $30;
  ASN1_SETOF       = $31;
  ASN1_IPADDR      = $40;
  ASN1_COUNTER     = $41;
  ASN1_GAUGE       = $42;
  ASN1_TIMETICKS   = $43;
  ASN1_OPAQUE      = $44;
  ASN1_COUNTER64   = $46;

  // class type masks
  ASN1_CL_APP   = $40;
  ASN1_CL_CTX   = $80;
  ASN1_CL_PRI   = $c0;

  //  context-specific class, tag #n
  ASN1_CTX0  = $80;
  ASN1_CTX1  = $81;
  ASN1_CTX2  = $82;
  ASN1_CTX3  = $83;
  ASN1_CTX4  = $84;
  ASN1_CTX5  = $85;
  ASN1_CTX6  = $86;
  ASN1_CTX7  = $87;
  ASN1_CTX8  = $88;
  ASN1_CTX9  = $89;

  //  context-specific class, constructed, tag #n
  ASN1_CTC0  = $a0;
  ASN1_CTC1  = $a1;
  ASN1_CTC2  = $a2;
  ASN1_CTC3  = $a3;
  ASN1_CTC4  = $a4;
  ASN1_CTC5  = $a5;
  ASN1_CTC6  = $a6;
  ASN1_CTC7  = $a7;
  ASN1_CTC8  = $a8;
  ASN1_CTC9  = $a9;

  ASN1_BOOLEAN: array[boolean] of byte = (
    $00,
    $ff);

  // LDAP types
  LDAP_ASN1_BIND_REQUEST      = $60;
  LDAP_ASN1_BIND_RESPONSE     = $61;
  LDAP_ASN1_UNBIND_REQUEST    = $42;
  LDAP_ASN1_SEARCH_REQUEST    = $63;
  LDAP_ASN1_SEARCH_ENTRY      = $64;
  LDAP_ASN1_SEARCH_DONE       = $65;
  LDAP_ASN1_SEARCH_REFERENCE  = $73;
  LDAP_ASN1_MODIFY_REQUEST    = $66;
  LDAP_ASN1_MODIFY_RESPONSE   = $67;
  LDAP_ASN1_ADD_REQUEST       = $68;
  LDAP_ASN1_ADD_RESPONSE      = $69;
  LDAP_ASN1_DEL_REQUEST       = $4a;
  LDAP_ASN1_DEL_RESPONSE      = $6b;
  LDAP_ASN1_MODIFYDN_REQUEST  = $6c;
  LDAP_ASN1_MODIFYDN_RESPONSE = $6d;
  LDAP_ASN1_COMPARE_REQUEST   = $6e;
  LDAP_ASN1_COMPARE_RESPONSE  = $6f;
  LDAP_ASN1_ABANDON_REQUEST   = $70;
  LDAP_ASN1_EXT_REQUEST       = $77;
  LDAP_ASN1_EXT_RESPONSE      = $78;
  LDAP_ASN1_CONTROLS          = $a0;


function AsnEncOidItem(Value: Int64): TAsnObject;
var
  r: PByte;
begin
  FastSetRawByteString(result, nil, 16);
  r := pointer(result);
  r^ := byte(Value) and $7f;
  inc(r);
  Value := Value shr 7;
  while Value <> 0 do
  begin
    r^ := byte(Value) or $80;
    inc(r);
    Value := Value shr 7;
  end;
  FakeLength(result, PAnsiChar(r) - pointer(result));
end;

function AsnDecOidItem(var Pos: integer; const Buffer: TAsnObject): integer;
var
  x: byte;
begin
  result := 0;
  repeat
    result := result shl 7;
    x := ord(Buffer[Pos]);
    inc(Pos);
    inc(result, x and $7F);
  until (x and $80) = 0;
end;

function AsnEncLen(Len: cardinal; dest: PByte): PtrInt;
var
  n: PtrInt;
  tmp: array[0..7] of byte;
begin
  if Len < $80 then
  begin
    dest^ := Len;
    result := 1;
    exit;
  end;
  n := 0;
  repeat
    tmp[n] := byte(Len);
    inc(n);
    Len := Len shr 8;
  until Len = 0;
  result := n + 1;
  dest^ := byte(n) or $80; // first byte is number of following bytes + $80
  repeat
    inc(dest);
    dec(n);
    dest^ := tmp[n]; // stored as big endian
  until n = 0;
end;

function AsnDecLen(var Start: integer; const Buffer: TAsnObject): cardinal;
var
  n: byte;
begin
  result := ord(Buffer[Start]);
  inc(Start);
  if result < $80 then
    exit;
  n := result and $7f;
  result := 0;
  repeat
    result := (result shl 8) + cardinal(Buffer[Start]);
    inc(Start);
    dec(n);
  until n = 0;
end;

function AsnEncInt(Value: Int64): TAsnObject;
var
  y: byte;
  neg: boolean;
  n: PtrInt;
  p: PByte;
  tmp: array[0..15] of byte;
begin
  result := '';
  neg := Value < 0;
  Value := Abs(Value);
  if neg then
    dec(Value);
  n := 0;
  repeat
    y := byte(Value);
    if neg then
      y := not y;
    tmp[n] := y;
    inc(n);
    Value := Value shr 8;
  until Value = 0;
  if neg then
  begin
    if y <= $7f then
    begin
      tmp[n] := $ff; // negative numbers start with ff or 8x
      inc(n);
    end;
  end
  else if y > $7F then
  begin
    tmp[n] := 0; // positive numbers start with a 0 or 0x..7x
    inc(n);
  end;
  FastSetRawByteString(result, nil, n);
  p := pointer(result);
  repeat
    dec(n);
    p^ := tmp[n]; // stored as big endian
    inc(p);
  until n = 0;
end;

function Asn(AsnType: integer;
  const Content: array of TAsnObject): TAsnObject; overload;
var
  tmp: array[0..7] of byte;
  i, len, al: PtrInt;
  p: PByte;
begin
  len := 0;
  for i := 0 to high(Content) do
    inc(len, length(Content[i]));
  al := AsnEncLen(len, @tmp);
  SetString(result, nil, 1 + al + len);
  p := pointer(result);
  p^ := AsnType;         // type
  inc(p);
  MoveFast(tmp, p^, al); // encoded length
  inc(p, al);
  for i := 0 to high(Content) do
  begin
    len := length(Content[i]);
    MoveFast(pointer(Content[i])^, p^, len); // content
    inc(p, len);
  end;
end;

function Asn(const Data: RawByteString; AsnType: integer = ASN1_OCTSTR): TAsnObject;
  overload; {$ifdef HASINLINE} inline; {$endif}
begin
  result := Asn(AsnType, [Data]);
end;

function Asn(Value: Int64; AsnType: integer = ASN1_INT): TAsnObject; overload;
begin
  result := Asn(AsnType, [AsnEncInt(Value)]);
end;

function Asn(Value: boolean): TAsnObject; overload;
begin
  result := Asn(ASN1_BOOL, [AsnEncInt(ASN1_BOOLEAN[Value])]);
end;

function AsnSeq(const Data: TAsnObject): TAsnObject;
begin
  result := Asn(ASN1_SEQ, [Data]);
end;

procedure AsnAdd(var Data: TAsnObject; const Buffer: TAsnObject);
  overload; {$ifdef HASINLINE} inline; {$endif}
begin
  AppendBufferToRawByteString(Data, Buffer);
end;

procedure AsnAdd(var Data: TAsnObject; const Buffer: TAsnObject;
  AsnType: integer); overload;
begin
  AppendBufferToRawByteString(Data, Asn(AsnType, [Buffer]));
end;

function IdToMib(Pos, EndPos: integer; const Buffer: RawByteString): RawUtf8;
var
  x, y: integer;
begin
  result := '';
  while Pos < EndPos do
  begin
    x := AsnDecOidItem(Pos, Buffer);
    if Pos = 2 then
    begin
      y := x div 40; // first byte = two first numbers modulo 40
      x := x mod 40;
      UInt32ToUtf8(y, result);
    end;
    Append(result, ['.', x]);
  end;
end;

function AsnNext(var Pos: integer; const Buffer: TAsnObject;
  out ValueType: integer): RawByteString;
var
  asntype, asnsize, n, l: integer;
  y: int64;
  x: byte;
  neg: boolean;
begin
  result := '';
  ValueType := ASN1_NULL;
  l := length(Buffer);
  if Pos > l then
    exit;
  asntype := ord(Buffer[Pos]);
  ValueType := asntype;
  inc(Pos);
  asnsize := AsnDecLen(Pos, Buffer);
  if (Pos + asnsize - 1) > l then
    exit;
  if (asntype and $20) <> 0 then
    result := copy(Buffer, Pos, asnsize)
  else
    case asntype of
      ASN1_INT,
      ASN1_ENUM,
      ASN1_BOOL:
        begin
          y := 0;
          neg := false;
          for n := 1 to asnsize do
          begin
            x := ord(Buffer[Pos]);
            if (n = 1) and
               (x > $7F) then
              neg := true;
            if neg then
              x := not x;
            y := (y shl 8) + x;
            inc(Pos);
          end;
          if neg then
            y := -(y + 1);
          result := ToUtf8(y);
        end;
      ASN1_COUNTER,
      ASN1_GAUGE,
      ASN1_TIMETICKS,
      ASN1_COUNTER64:
        begin
          y := 0;
          for n := 1 to asnsize do
          begin
            y := (y shl 8) + ord(Buffer[Pos]);
            inc(Pos);
          end;
          result := ToUtf8(y);
        end;
      ASN1_OBJID:
        begin
          result := IdToMib(Pos, Pos + asnsize, Buffer);
          inc(Pos, asnsize);
        end;
      ASN1_IPADDR:
        begin
          case asnsize of
            4:
              IP4Text(pointer(@Buffer[Pos]), RawUtf8(result));
            16:
              IP6Text(pointer(@Buffer[Pos]), RawUtf8(result));
          else
            BinToHexLower(@Buffer[Pos], asnsize, RawUtf8(result));
          end;
          inc(Pos, asnsize);
        end;
      ASN1_NULL:
        inc(Pos, asnsize);
    else
      // ASN1_UTF8STRING, ASN1_OCTSTR, ASN1_OPAQUE or unknown
      begin
        result := copy(Buffer, Pos, asnsize); // return as raw binary
        inc(Pos, asnsize);
      end;
    end;
end;

function DNToCN(const DN: RawUtf8): RawUtf8;
var
  p: PUtf8Char;
  DC, OU, CN, PartType, Value: RawUtf8;
begin
  p := pointer(DN);
  while p <> nil do
  begin
    GetNextItemTrimed(p, '=', PartType);
    GetNextItemTrimed(p, ',', Value);
    if (PartType = '') or
       (Value = '') then
      raise ENetSock.CreateFmt('DNToCN(%s): invalid Distinguished Name', [DN]);
    UpperCaseSelf(PartType);
    if PartType = 'DC' then
    begin
      if DC <> '' then
        DC := DC +'.';
      DC := DC + Value;
    end
    else if PartType = 'OU' then
      Prepend(OU, ['/', Value])
    else if PartType = 'CN' then
      Prepend(CN, ['/', Value]);
  end;
  result := DC + OU + CN;
end;

{$ifdef ASNDEBUG} // not used nor fully tested

function IntMibToStr(const Value: RawByteString): RawUtf8;
var
  i, y: integer;
begin
  y := 0;
  for i := 1 to length(Value) - 1 do
    y := (y shl 8) + ord(Value[i]);
  UInt32ToUtf8(y, result);
end;

function MibToId(Mib: RawUtf8): RawByteString;
var
  x: integer;

  function WalkInt(var s: RawUtf8): integer;
  var
    x: integer;
    t: RawByteString;
  begin
    x := PosExChar('.', s);
    if x < 1 then
    begin
      t := s;
      s := '';
    end
    else
    begin
      t := copy(s, 1, x - 1);
      s := copy(s, x + 1, length(s) - x);
    end;
    result := Utf8ToInteger(t, 0);
  end;

begin
  result := '';
  x := WalkInt(Mib);
  x := x * 40 + WalkInt(Mib);
  result := AsnEncOidItem(x);
  while Mib <> '' do
  begin
    x := WalkInt(Mib);
    Append(result, [AsnEncOidItem(x)]);
  end;
end;

function AsnEncUInt(Value: integer): RawByteString;
var
  x, y: integer;
  neg: boolean;
begin
  neg := Value < 0;
  x := Value;
  if neg then
    x := x and $7FFFFFFF;
  result := '';
  repeat
    y := x mod 256;
    x := x div 256;
    Prepend(result, [AnsiChar(y)]);
  until x = 0;
  if neg then
    result[1] := AnsiChar(ord(result[1]) or $80);
end;

function DumpExStr(const Buffer: RawByteString): RawUtf8;
var
  n: integer;
  x: byte;
begin
  result := '';
  for n := 1 to length(Buffer) do
  begin
    x := ord(Buffer[n]);
    if x in [65..90, 97..122] then
      Append(result, [' +''', AnsiChar(x), ''''])
    else
      Append(result, [' +#$', BinToHexDisplayLowerShort(@x, 1)]);
  end;
end;

function AsnDump(const Value: TAsnObject): RawUtf8;
var
  i, at, x, n: integer;
  s, indent: RawUtf8;
  il: TIntegerDynArray;
begin
  result := '';
  i := 1;
  indent := '';
  while i < length(Value) do
  begin
    for n := length(il) - 1 downto 0 do
    begin
      x := il[n];
      if x <= i then
      begin
        DeleteInteger(il, n);
        Delete(indent, 1, 2);
      end;
    end;
    s := AsnNext(i, Value, at);
    Append(result, [indent, '$', IntToHex(at, 2)]);
    if (at and $20) > 0 then
    begin
      x := length(s);
      Append(result, [' constructed: length ', x]);
      Append(indent, ['  ']);
      AddInteger(il, x + i - 1);
    end
    else
    begin
      case at of
        ASN1_BOOL:
          AppendToRawUtf8(result, ' BOOL: ');
        ASN1_INT:
          AppendToRawUtf8(result, ' INT: ');
        ASN1_ENUM:
          AppendToRawUtf8(result, ' ENUM: ');
        ASN1_COUNTER:
          AppendToRawUtf8(result, ' COUNTER: ');
        ASN1_GAUGE:
          AppendToRawUtf8(result, ' GAUGE: ');
        ASN1_TIMETICKS:
          AppendToRawUtf8(result, ' TIMETICKS: ');
        ASN1_OCTSTR:
          AppendToRawUtf8(result, ' OCTSTR: ');
        ASN1_OPAQUE:
          AppendToRawUtf8(result, ' OPAQUE: ');
        ASN1_OBJID:
          AppendToRawUtf8(result, ' OBJID: ');
        ASN1_IPADDR:
          AppendToRawUtf8(result, ' IPADDR: ');
        ASN1_NULL:
          AppendToRawUtf8(result, ' NULL: ');
        ASN1_COUNTER64:
          AppendToRawUtf8(result, ' COUNTER64: ');
      else // other
        AppendToRawUtf8(result, ' unknown: ');
      end;
      if IsBinaryString(s) then
        s := DumpExStr(s);
      AppendToRawUtf8(result, s);
    end;
    AppendCharToRawUtf8(result, #$0d);
    AppendCharToRawUtf8(result, #$0a);
  end;
end;

{$endif ASNDEBUG}


{ **************** LDAP Response Storage }

{ TLdapAttribute }

constructor TLdapAttribute.Create(const AttrName: RawUtf8);
begin
  inherited Create;
  fAttributeName := AttrName;
  fIsBinary := StrPosI(';BINARY', pointer(AttrName)) <> nil;
  SetLength(fList, 1); // optimized for a single value (most used case)
end;

procedure TLdapAttribute.Add(const aValue: RawByteString);
begin
  AddRawUtf8(fList, fCount, aValue);
end;

function TLdapAttribute.GetReadable(index: PtrInt): RawUtf8;
begin
  if (self = nil) or
     (index >= fCount) then
    result := ''
  else
  begin
    result := fList[index];
    if fIsBinary then
      result := BinToBase64(result)
    else if IsBinaryString(result) then
      result := LogEscapeFull(result);
  end;
end;

function TLdapAttribute.GetRaw(index: PtrInt): RawByteString;
begin
  if (self = nil) or
     (index >= fCount) then
    result := ''
  else
    result := fList[index];
end;


{ TLdapAttributeList }

destructor TLdapAttributeList.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TLdapAttributeList.Clear;
begin
  ObjArrayClear(fItems);
end;

function TLdapAttributeList.Count: integer;
begin
  result := length(fItems);
end;

function TLdapAttributeList.FindIndex(const AttributeName: RawUtf8): PtrInt;
begin
  if self <> nil then
    for result := 0 to length(fItems) - 1 do
      if IdemPropNameU(fItems[result].AttributeName, AttributeName) then
        exit;
  result := -1;
end;

function TLdapAttributeList.Find(const AttributeName: RawUtf8): TLdapAttribute;
var
  i: PtrInt;
begin
  i := FindIndex(AttributeName);
  if i >= 0 then
    result := fItems[i]
  else
    result := nil;
end;

function TLdapAttributeList.Get(const AttributeName: RawUtf8): RawUtf8;
begin
  result := Find(AttributeName).GetReadable(0);
end;

function TLdapAttributeList.Add(const AttributeName: RawUtf8): TLdapAttribute;
begin
  result := TLdapAttribute.Create(AttributeName);
  ObjArrayAdd(fItems, result);
end;

function TLdapAttributeList.Add(const AttributeName: RawUtf8;
  const AttributeValue: RawByteString): TLdapAttribute;
begin
  result := Add(AttributeName);
  result.Add(AttributeValue);
end;

procedure TLdapAttributeList.Delete(const AttributeName: RawUtf8);
begin
  ObjArrayDelete(fItems, FindIndex(AttributeName));
end;


{ TLdapResult }

constructor TLdapResult.Create;
begin
  inherited Create;
  fAttributes := TLdapAttributeList.Create;
end;

destructor TLdapResult.Destroy;
begin
  fAttributes.Free;
  inherited Destroy;
end;

function TLdapResult.CopyObjectSid(out objectSid: TSid): boolean;
var
  SidAttr: TLdapAttribute;
  SidBinary: RawByteString;
  SidBytesLen: PtrInt;
begin
  result := false;
  SidAttr := Attributes.Find('objectSid');
  if SidAttr = nil then
    exit;
  SidBinary := SidAttr.GetRaw;
  SidBytesLen := length(SidBinary);
  // Sid can fit in the struct TSid
  if (SidBytesLen <= SizeOf(objectSid)) and
     // Sid size is coherent with the sub authority count
     (SidBytesLen = Sizeof(byte) * 2 + SizeOf(TSidAuth) +
        SizeOf(cardinal) * PSid(SidBinary)^.SubAuthorityCount) then
  begin
    MoveFast(SidBinary[1], objectSid, SidBytesLen);
    result := true;
  end;
end;

function TLdapResult.CopyObjectGUID(out objectGUID: TGuid): boolean;
var
  GuidAttr: TLdapAttribute;
  GuidBinary: RawByteString;
begin
  result := false;
  GuidAttr := Attributes.Find('objectGUID');
  if GuidAttr = nil then
    exit;
  GuidBinary := GuidAttr.GetRaw;
  if length(GuidBinary) = SizeOf(TGuid) then
  begin
    objectGUID := PGuid(GuidBinary)^;
    result := true;
  end;
end;


{ TLdapResultList }

destructor TLdapResultList.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TLdapResultList.Clear;
begin
  ObjArrayClear(fItems, fCount);
  fCount := 0;
end;

function TLdapResultList.Add: TLdapResult;
begin
  result := TLdapResult.Create;
  ObjArrayAddCount(fItems, result, fCount);
end;

function TLdapResultList.Dump: RawUtf8;
var
  i, j, k: PtrInt;
  res: TLdapResult;
  attr: TLdapAttribute;
begin
  result := 'results: ' + ToUtf8(Count) + CRLF + CRLF;
  for i := 0 to Count - 1 do
  begin
    result := result + 'result: ' + ToUtf8(i) + CRLF;
    res := Items[i];
    result := result + '  Object: ' + res.ObjectName + CRLF;
    for j := 0 to res.Attributes.Count - 1 do
    begin
      attr := res.Attributes.Items[j];
      result := result + '  Attribute: ' + attr.AttributeName + CRLF;
      for k := 0 to attr.Count - 1 do
        result := result + '    ' + attr.GetReadable(k) + CRLF;
    end;
  end;
end;


{ **************** LDAP Client Class }

{ TLdapClient }

constructor TLdapClient.Create;
begin
  inherited Create;
  fReferals := TRawUtf8List.Create;
  fTargetHost := cLocalhost;
  fTargetPort := '389';
  fTimeout := 60000;
  fVersion := 3;
  fSearchScope := SS_WholeSubtree;
  fSearchAliases := SA_Always;
  fSearchResult := TLdapResultList.Create;
end;

destructor TLdapClient.Destroy;
begin
  fSock.Free;
  fSearchResult.Free;
  fReferals.Free;
  inherited Destroy;
end;

class function TLdapClient.GetErrorString(ErrorCode: integer): RawUtf8;
begin
  case ErrorCode of
    LDAP_RES_SUCCESS:
      result := 'Success';
    LDAP_RES_OPERATIONS_ERROR:
      result := 'Operations error';
    LDAP_RES_PROTOCOL_ERROR:
      result := 'Protocol error';
    LDAP_RES_TIME_LIMIT_EXCEEDED:
      result := 'Time limit Exceeded';
    LDAP_RES_SIZE_LIMIT_EXCEEDED:
      result := 'Size limit Exceeded';
    LDAP_RES_COMPARE_FALSE:
      result := 'Compare false';
    LDAP_RES_COMPARE_TRUE:
      result := 'Compare true';
    LDAP_RES_AUTH_METHOD_NOT_SUPPORTED:
      result := 'Auth method not supported';
    LDAP_RES_STRONGER_AUTH_REQUIRED:
      result := 'Strong auth required';
    LDAP_RES_REFERRAL:
      result := 'Referral';
    LDAP_RES_ADMIN_LIMIT_EXCEEDED:
      result := 'Admin limit exceeded';
    LDAP_RES_UNAVAILABLE_CRITICAL_EXTENSION:
      result := 'Unavailable critical extension';
    LDAP_RES_CONFIDENTIALITY_REQUIRED:
      result := 'Confidentality required';
    LDAP_RES_SASL_BIND_IN_PROGRESS:
      result := 'Sasl bind in progress';
    LDAP_RES_NO_SUCH_ATTRIBUTE:
      result := 'No such attribute';
    LDAP_RES_UNDEFINED_ATTRIBUTE_TYPE:
      result := 'Undefined attribute type';
    LDAP_RES_INAPPROPRIATE_MATCHING:
      result := 'Inappropriate matching';
    LDAP_RES_CONSTRAINT_VIOLATION:
      result := 'Constraint violation';
    LDAP_RES_ATTRIBUTE_OR_VALUE_EXISTS:
      result := 'Attribute or value exists';
    LDAP_RES_INVALID_ATTRIBUTE_SYNTAX:
      result := 'Invalid attribute syntax';
    LDAP_RES_NO_SUCH_OBJECT:
      result := 'No such object';
    LDAP_RES_ALIAS_PROBLEM:
      result := 'Alias problem';
    LDAP_RES_INVALID_DN_SYNTAX:
      result := 'Invalid DN syntax';
    LDAP_RES_ALIAS_DEREFERENCING_PROBLEM:
      result := 'Alias dereferencing problem';
    LDAP_RES_INAPPROPRIATE_AUTHENTICATION:
      result := 'Inappropriate authentication';
    LDAP_RES_INVALID_CREDENTIALS:
      result := 'Invalid credentials';
    LDAP_RES_INSUFFICIENT_ACCESS_RIGHTS:
      result := 'Insufficient access rights';
    LDAP_RES_BUSY:
      result := 'Busy';
    LDAP_RES_UNAVAILABLE:
      result := 'Unavailable';
    LDAP_RES_UNWILLING_TO_PERFORM:
      result := 'Unwilling to perform';
    LDAP_RES_LOOP_DETECT:
      result := 'Loop detect';
    LDAP_RES_NAMING_VIOLATION:
      result := 'Naming violation';
    LDAP_RES_OBJECT_CLASS_VIOLATION:
      result := 'Object class violation';
    LDAP_RES_NOT_ALLOWED_ON_NON_LEAF:
      result := 'Not allowed on non leaf';
    LDAP_RES_NOT_ALLOWED_ON_RDN:
      result := 'Not allowed on RDN';
    LDAP_RES_ENTRY_ALREADY_EXISTS:
      result := 'Entry already exists';
    LDAP_RES_OBJECT_CLASS_MODS_PROHIBITED:
      result := 'Object class mods prohibited';
    LDAP_RES_AFFECTS_MULTIPLE_DSAS:
      result := 'Affects multiple DSAs';
    LDAP_RES_OTHER:
      result := 'Other';
  else
    FormatUtf8('unknown #%', [ErrorCode], result);
  end;
end;

function TLdapClient.ReceiveString(Size: integer): RawByteString;
begin
  FastSetRawByteString(result, nil, Size);
  fSock.SockInRead(pointer(result), Size);
end;

function TLdapClient.Connect: boolean;
begin
  FreeAndNil(fSock);
  result := false;
  fSeq := 0;
  try
    fSock := TCrtSocket.Open(
      fTargetHost, fTargetPort, nlTcp, fTimeOut, fFullTls, fTlsContext);
    fSock.CreateSockIn;
    result := fSock.SockConnected;
  except
    on E: ENetSock do
      FreeAndNil(fSock);
  end;
end;

function TLdapClient.BuildPacket(const Asn1Data: TAsnObject): TAsnObject;
begin
  inc(fSeq);
  result := Asn(ASN1_SEQ, [
    Asn(fSeq),
    Asn1Data]);
end;

function TLdapClient.GetRootDN: RawUtf8;
begin
  if (fRootDN = '') and Connected then
    fRootDN := DiscoverRootDN;
  result := fRootDN;
end;

procedure TLdapClient.SendPacket(const Asn1Data: TAsnObject);
begin
  fSock.SockSendFlush(BuildPacket(Asn1Data));
end;

function TLdapClient.ReceiveResponse: TAsnObject;
var
  b: byte;
  len, pos: integer;
begin
  result := '';
  fFullResult := '';
  try
    // receive ASN type
    fSock.SockInRead(pointer(@b), 1);
    if b <> ASN1_SEQ then
      exit;
    result := AnsiChar(b);
    // receive length
    fSock.SockInRead(pointer(@b), 1);
    AppendBufferToRawByteString(result, b, 1);
    if b >= $80 then // $8x means x bytes of length
      AsnAdd(result, ReceiveString(b and $7f));
    // decode length of LDAP packet
    pos := 2;
    len := AsnDecLen(pos, result);
    // retrieve rest of LDAP packet
    if len > 0 then
      AsnAdd(result, ReceiveString(len));
  except
    on E: ENetSock do
    begin
      result := '';
      exit;
    end;
  end;
  fFullResult := result;
end;

// see https://ldap.com/ldapv3-wire-protocol-reference-ldap-result

function TLdapClient.DecodeResponse(const Asn1Response: TAsnObject): TAsnObject;
var
  i, x, numseq: integer;
  asntype: integer;
  s, t: TAsnObject;
begin
  result := '';
  fResultCode := -1;
  fResultString := '';
  fResponseCode := -1;
  fResponseDN := '';
  fReferals.Clear;
  i := 1;
  AsnNext(i, Asn1Response, asntype); // initial ANS1_SEQ
  numseq := Utf8ToInteger(AsnNext(i, Asn1Response, asntype), 0);
  if (asntype <> ASN1_INT) or
     (numseq <> fSeq) then
    exit;
  AsnNext(i, Asn1Response, fResponseCode);
  if fResponseCode in [LDAP_ASN1_BIND_RESPONSE, LDAP_ASN1_SEARCH_DONE,
    LDAP_ASN1_MODIFY_RESPONSE, LDAP_ASN1_ADD_RESPONSE, LDAP_ASN1_DEL_RESPONSE,
    LDAP_ASN1_MODIFYDN_RESPONSE, LDAP_ASN1_COMPARE_RESPONSE,
    LDAP_ASN1_EXT_RESPONSE] then
  begin
    fResultCode := Utf8ToInteger(AsnNext(i, Asn1Response, asntype), -1);
    fResponseDN := AsnNext(i, Asn1Response, asntype);   // matchedDN
    fResultString := AsnNext(i, Asn1Response, asntype); // diagnosticMessage
    if fResultString = '' then
      fResultString := GetErrorString(fResultCode);
    if fResultCode = LDAP_RES_REFERRAL then
    begin
      s := AsnNext(i, Asn1Response, asntype);
      if asntype = ASN1_CTC3 then
      begin
        x := 1;
        while x < length(s) do
        begin
          t := AsnNext(x, s, asntype);
          fReferals.Add(t);
        end;
      end;
    end;
  end;
  result := copy(Asn1Response, i, length(Asn1Response) - i + 1); // body
end;

function TLdapClient.SendAndReceive(const Asn1Data: TAsnObject): TAsnObject;
begin
  SendPacket(Asn1Data);
  result := DecodeResponse(ReceiveResponse);
end;

function TLdapClient.SaslDigestMd5(const Value: RawUtf8): RawUtf8;
var
  v, ha0, ha1, ha2, nonce, cnonce, nc, realm, authzid, qop, uri, resp: RawUtf8;
  p, s: PUtf8Char;
  hasher: TMd5;
  dig: TMd5Digest;
begin
  // see https://en.wikipedia.org/wiki/Digest_access_authentication
  p := pointer(Value);
  while p <> nil do
  begin
    v := GetNextItem(p);
    s := pointer(v);
    if IdemPChar(s, 'NONCE=') then
      UnquoteStr(p + 6, nonce)
    else if IdemPChar(s, 'REALM=') then
      UnquoteStr(p + 6, realm)
    else if IdemPChar(s, 'AUTHZID=') then
      UnquoteStr(p + 8, authzid);
  end;
  cnonce := Int64ToHexLower(Random64);
  nc := '00000001';
  qop := 'auth';
  uri := 'ldap/' + LowerCaseU(fSock.Server);
  hasher.Init;
  hasher.Update(fUserName);
  hasher.Update(':');
  hasher.Update(realm);
  hasher.Update(':');
  hasher.Update(fPassword);
  hasher.Final(dig);
  FastSetString(ha0, @dig, SizeOf(dig)); // ha0 = md5 binary, not hexa
  ha1 := FormatUtf8('%:%:%', [ha0, nonce, cnonce]);
  if authzid <> '' then
    Append(ha1, [':', authzid]);
  ha1 := Md5(ha1); // Md5() = into lowercase hexadecimal
  ha2 := Md5(FormatUtf8('AUTHENTICATE:%', [uri]));
  resp := Md5(FormatUtf8('%:%:%:%:%:%', [ha1, nonce, nc, cnonce, qop, ha2]));
  FormatUtf8('username="%",realm="%",nonce="%",cnonce="%",nc=%,qop=%,' +
    'digest-uri="%",response=%',
    [fUserName, realm, nonce, cnonce, nc, qop, uri, resp], result);
end;

// https://ldap.com/ldapv3-wire-protocol-reference-search

function TLdapClient.TranslateFilter(const Filter: RawUtf8): TAsnObject;
var
  x, dn: integer;
  c: Ansichar;
  s, t, l, r, attr, rule: RawUtf8;
begin
  result := '';
  if Filter = '' then
    exit;
  s := Filter;
  if Filter[1] = '(' then
    for x := length(Filter) downto 2 do
      if Filter[x] = ')' then
      begin
        s := copy(Filter, 2, x - 2); // get value between (...)
        break;
      end;
  if s = '' then
    exit;
  case s[1] of
    '!':
      // NOT rule (recursive call)
      result := Asn(TranslateFilter(GetBetween('(', ')', s)), ASN1_CTC2);
    '&':
      // and rule (recursive call)
      begin
        repeat
          t := GetBetween('(', ')', s);
          s := SeparateRightU(s, t);
          if s <> '' then
            if s[1] = ')' then
              System.Delete(s, 1, 1);
          AsnAdd(result, TranslateFilter(t));
        until s = '';
        result := Asn(result, ASN1_CTC0);
      end;
    '|':
      // or rule (recursive call)
      begin
        repeat
          t := GetBetween('(', ')', s);
          s := SeparateRightU(s, t);
          if s <> '' then
            if s[1] = ')' then
              System.Delete(s, 1, 1);
          AsnAdd(result, TranslateFilter(t));
        until s = '';
        result := Asn(result, ASN1_CTC1);
      end;
    else
      begin
        l := TrimU(SeparateLeft(s, '='));
        r := TrimU(SeparateRight(s, '='));
        if l <> '' then
        begin
          c := l[length(l)];
          case c of
            ':':
              // Extensible match
              begin
                System.Delete(l, length(l), 1);
                dn := ASN1_BOOLEAN[false];
                attr := '';
                rule := '';
                if mormot.core.base.PosEx(':dn', l) > 0 then
                begin
                  dn := ASN1_BOOLEAN[true];
                  l := StringReplaceAll(l, ':dn', '');
                end;
                attr := TrimU(SeparateLeft(l, ':'));
                rule := TrimU(SeparateRight(l, ':'));
                if rule = l then
                  rule := '';
                if rule <> '' then
                  result := Asn(rule, ASN1_CTX1);
                if attr <> '' then
                  AsnAdd(result, attr, ASN1_CTX2);
                AsnAdd(result, DecodeTriplet(r, '\'), ASN1_CTX3);
                AsnAdd(result, AsnEncInt(dn), ASN1_CTX4);
                result := Asn(result, ASN1_CTC9);
              end;
            '~':
              // Approx match
              begin
                System.Delete(l, length(l), 1);
                result := Asn(ASN1_CTC8, [
                  Asn(l),
                  Asn(DecodeTriplet(r, '\'))]);
              end;
            '>':
              // Greater or equal match
              begin
                System.Delete(l, length(l), 1);
                result := Asn(ASN1_CTC5, [
                   Asn(l),
                   Asn(DecodeTriplet(r, '\'))]);
              end;
            '<':
              // Less or equal match
              begin
                System.Delete(l, length(l), 1);
                result := Asn(ASN1_CTC6, [
                   Asn(l),
                   Asn(DecodeTriplet(r, '\'))]);
              end;
          else
            // present
            if r = '*' then
              result := Asn(l, ASN1_CTX7)
            else
              if PosExChar('*', r) > 0 then
              // substrings
              begin
                s := Fetch(r, '*');
                if s <> '' then
                  result := Asn(DecodeTriplet(s, '\'), ASN1_CTX0);
                while r <> '' do
                begin
                  if PosExChar('*', r) <= 0 then
                    break;
                  s := Fetch(r, '*');
                  AsnAdd(result, DecodeTriplet(s, '\'), ASN1_CTX1);
                end;
                if r <> '' then
                  AsnAdd(result, DecodeTriplet(r, '\'), ASN1_CTX2);
                result := Asn(ASN1_CTC4, [
                   Asn(l),
                   AsnSeq(result)]);
              end
              else
              begin
                // Equality match
                result := Asn(ASN1_CTC3, [
                   Asn(l),
                   Asn(DecodeTriplet(r, '\'))]);
              end;
          end;
        end;
      end;
  end;
end;

function TLdapClient.Login: boolean;
begin
  result := false;
  if not Connect then
    exit;
  result := true;
end;

// see https://ldap.com/ldapv3-wire-protocol-reference-bind

function TLdapClient.Bind: boolean;
begin
  SendAndReceive(Asn(LDAP_ASN1_BIND_REQUEST, [
                   Asn(fVersion),
                   Asn(fUserName),
                   Asn(fPassword, ASN1_CTX0)]));
  result := fResultCode = LDAP_RES_SUCCESS;
  fBound := result;
end;

function TLdapClient.BindSaslDigestMd5: boolean;
var
  x, xt: integer;
  s, t, digreq: TAsnObject;
begin
  result := false;
  if fPassword = '' then
    result := Bind
  else
  begin
    digreq := Asn(LDAP_ASN1_BIND_REQUEST, [
                Asn(fVersion),
                Asn(''),
                Asn(ASN1_CTC3, [
                  Asn('DIGEST-MD5')])]);
    t := SendAndReceive(digreq);
    if fResultCode = LDAP_RES_SASL_BIND_IN_PROGRESS then
    begin
      s := t;
      x := 1;
      t := AsnNext(x, s, xt);
      SendAndReceive(Asn(LDAP_ASN1_BIND_REQUEST, [
                       Asn(fVersion),
                       Asn(''),
                       Asn(ASN1_CTC3, [
                         Asn('DIGEST-MD5'),
                         Asn(SaslDigestMd5(t))])]));
      if fResultCode = LDAP_RES_SASL_BIND_IN_PROGRESS then
        SendAndReceive(digreq);
      result := fResultCode = LDAP_RES_SUCCESS;
    end;
  end;
end;

// TODO: GSSAPI SASL authentication using mormot.lib.gssapi/sspi units
// - see https://github.com/go-ldap/ldap/blob/master/bind.go#L561


// https://ldap.com/ldapv3-wire-protocol-reference-unbind

function TLdapClient.Logout: boolean;
begin
  SendPacket(Asn('', LDAP_ASN1_UNBIND_REQUEST));
  FreeAndNil(fSock);
  result := true;
  fBound := false;
  fRootDN := '';
end;

// https://ldap.com/ldapv3-wire-protocol-reference-modify

function TLdapClient.Modify(const Obj: RawUtf8; Op: TLdapModifyOp;
  Value: TLdapAttribute): boolean;
var
  query: TAsnObject;
  i: integer;
begin
  for i := 0 to Value.Count -1 do
    AsnAdd(query, Asn(Value.GetRaw(i)));
  SendAndReceive(Asn(LDAP_ASN1_MODIFY_REQUEST, [
                   Asn(obj),
                   Asn(ASN1_SEQ, [
                     Asn(ASN1_SEQ, [
                       Asn(ord(Op), ASN1_ENUM),
                       Asn(ASN1_SEQ, [
                         Asn(Value.AttributeName),
                         Asn(query, ASN1_SETOF)])])])]));
  result := fResultCode = LDAP_RES_SUCCESS;
end;

// https://ldap.com/ldapv3-wire-protocol-reference-add

function TLdapClient.Add(const Obj: RawUtf8; Value: TLdapAttributeList): boolean;
var
  query, sub: TAsnObject;
  attr: TLdapAttribute;
  i, j: PtrInt;
begin
  for i := 0 to Value.Count - 1 do
  begin
    attr := Value.Items[i];
    sub := '';
    for j := 0 to attr.Count - 1 do
      AsnAdd(sub, Asn(attr.GetRaw(j)));
    Append(query, [
      Asn(ASN1_SEQ, [
        Asn(attr.AttributeName),
        Asn(ASN1_SETOF, [sub])])]);
  end;
  SendAndReceive(Asn(LDAP_ASN1_ADD_REQUEST, [
                   Asn(obj),
                   AsnSeq(query)]));
  result := fResultCode = LDAP_RES_SUCCESS;
end;

function TLdapClient.AddComputer(const ComputerParentDN, ComputerName: RawUtf8;
  out ErrorMessage: RawUtf8; const Password: SpiUtf8; DeleteIfPresent: boolean): boolean;
var
  PwdU8: SpiUtf8;
  ComputerDN: RawUtf8;
  PwdU16: RawByteString;
  Attributes: TLdapAttributeList;
begin
  result := false;
  ComputerDN := 'CN=' + ComputerName + ',' + ComputerParentDN;
  // Search if computer is already present in the domain
  if not Search(ComputerDN, false, '', []) then
  begin
    ErrorMessage := GetErrorString(ResultCode);
    exit;
  end;
  if SearchResult.Count > 0 then
    if DeleteIfPresent then
      Delete(ComputerDN)
    else
    begin
      ErrorMessage := 'Computer is already present';
      result := true;
      exit;
    end;
  Attributes := TLDAPAttributeList.Create;
  try
    Attributes.Add('objectClass', 'computer');
    Attributes.Add('cn', ComputerName);
    Attributes.Add('sAMAccountName', UpperCase(ComputerName) + '$');
    Attributes.Add('userAccountControl', '4096');
    if Password <> '' then
    begin
      PwdU8 := '"' + Password + '"';
      PwdU16 := Utf8DecodeToUnicodeRawByteString(PwdU8);
      Attributes.Add('unicodePwd', PwdU16);
    end;
    result := Add(ComputerDN, Attributes);
    if not result then
      ErrorMessage := GetErrorString(ResultCode);
  finally
    Attributes.Free;
    FillZero(PwdU8);
    FillZero(PwdU16);
  end;
end;

// https://ldap.com/ldapv3-wire-protocol-reference-delete

function TLdapClient.Delete(const Obj: RawUtf8): boolean;
begin
  SendAndReceive(Asn(obj, LDAP_ASN1_DEL_REQUEST));
  result := fResultCode = LDAP_RES_SUCCESS;
end;

// https://ldap.com/ldapv3-wire-protocol-reference-modify-dn

function TLdapClient.ModifyDN(const obj, newRdn, newSuperior: RawUtf8;
  DeleteOldRdn: boolean): boolean;
var
  query: TAsnObject;
begin
  query := Asn(obj);
  Append(query, [Asn(newRdn), Asn(DeleteOldRdn)]);
  if newSuperior <> '' then
    AsnAdd(query, Asn(newSuperior, ASN1_CTX0));
  SendAndReceive(Asn(query, LDAP_ASN1_MODIFYDN_REQUEST));
  result := fResultCode = LDAP_RES_SUCCESS;
end;

// https://ldap.com/ldapv3-wire-protocol-reference-compare

function TLdapClient.Compare(const Obj, AttributeValue: RawUtf8): boolean;
begin
  SendAndReceive(Asn(LDAP_ASN1_COMPARE_REQUEST, [
                   Asn(obj),
                   Asn(ASN1_SEQ, [
                     Asn(TrimU(SeparateLeft(AttributeValue, '='))),
                     Asn(TrimU(SeparateRight(AttributeValue, '=')))])]));
  result := fResultCode = LDAP_RES_SUCCESS;
end;

// https://ldap.com/ldapv3-wire-protocol-reference-search

function TLdapClient.Search(const BaseDN: RawUtf8; TypesOnly: boolean;
  Filter: RawUtf8; const Attributes: array of RawByteString): boolean;
var
  s, filt, attr, resp: TAsnObject;
  u: RawUtf8;
  n, i, x: integer;
  r: TLdapResult;
  a: TLdapAttribute;
begin
  // see https://ldap.com/ldapv3-wire-protocol-reference-search
  fSearchResult.Clear;
  fReferals.Clear;
  if Filter = '' then
    Filter := '(objectclass=*)';
  filt := TranslateFilter(Filter);
  if filt = '' then
    filt := Asn('', ASN1_NULL);
  for n := 0 to high(Attributes) do
    AsnAdd(attr, Asn(Attributes[n]));
  s := Asn(LDAP_ASN1_SEARCH_REQUEST, [
           Asn(BaseDN),
           Asn(ord(fSearchScope),   ASN1_ENUM),
           Asn(ord(fSearchAliases), ASN1_ENUM),
           Asn(fSearchSizeLimit),
           Asn(fSearchTimeLimit),
           Asn(TypesOnly),
           filt,
           AsnSeq(attr)]);
  if fSearchPageSize > 0 then
    Append(s, [Asn(
        Asn(ASN1_SEQ, [
           Asn('1.2.840.113556.1.4.319'), // controlType: pagedresultsControl
           Asn(false), // criticality: false
           Asn(Asn(ASN1_SEQ, [
             Asn(fSearchPageSize),
             Asn(fSearchCookie)]))]), LDAP_ASN1_CONTROLS)]);
  SendPacket(s);
  repeat
    resp := DecodeResponse(ReceiveResponse);
    if fResponseCode = LDAP_ASN1_SEARCH_ENTRY then
    begin
      r := fSearchResult.Add;
      n := 1;
      r.ObjectName := AsnNext(n, resp, x);
      AsnNext(n, resp, x);
      if x = ASN1_SEQ then
      begin
        while n < length(resp) do
        begin
          s := AsnNext(n, resp, x);
          if x = ASN1_SEQ then
          begin
            i := n + length(s);
            u := AsnNext(n, resp, x);
            a := r.Attributes.Add(u);
            AsnNext(n, resp, x);
            if x = ASN1_SETOF then
              while n < i do
              begin
                u := AsnNext(n, resp, x);
                a.Add(u);
              end;
          end;
        end;
      end;
    end;
    if fResponseCode = LDAP_ASN1_SEARCH_REFERENCE then
    begin
      n := 1;
      while n < length(resp) do
        fReferals.Add(AsnNext(n, resp, x));
    end;
  until fResponseCode = LDAP_ASN1_SEARCH_DONE;
  n := 1;
  AsnNext(n, resp, x);
  if x = LDAP_ASN1_CONTROLS then
  begin
    AsnNext(n, resp, x);
    if x = ASN1_SEQ then
    begin
      s := AsnNext(n, resp, x);
      if s = '1.2.840.113556.1.4.319' then
      begin
        s := AsnNext(n, resp, x); // searchControlValue
        n := 1;
        AsnNext(n, s, x);
        if x = ASN1_SEQ then
        begin
          // total number of result records, if known, otherwise 0
          AsnNext(n, s, x);
          // active search cookie, empty when done
          fSearchCookie := AsnNext(n, s, x);
        end;
      end;
    end;
  end;
  result := fResultCode = LDAP_RES_SUCCESS;
end;

function TLdapClient.SearchFirst(const BaseDN: RawUtf8; Filter: RawUtf8;
  const Attributes: array of RawByteString): TLdapResult;
begin
  result := nil;
  if Search(BaseDN, false, Filter, Attributes) and
     (SearchResult.Count > 0) then
    result := SearchResult.Items[0];
end;

function TLdapClient.SearchObject(const ObjectDN: RawUtf8;
  const Attributes: array of RawByteString): TLdapResult;
var
  PreviousSearchScope: TLdapSearchScope;
begin
  PreviousSearchScope := SearchScope;
  try
    SearchScope := SS_BaseObject;
    result := SearchFirst(ObjectDN, '', Attributes);
  finally
    SearchScope := PreviousSearchScope;
  end;
end;

// https://ldap.com/ldapv3-wire-protocol-reference-extended

function TLdapClient.Extended(const Oid, Value: RawUtf8): boolean;
var
  query, decoded: TAsnObject;
  pos, xt: integer;
begin
  query := Asn(Oid, ASN1_CTX0);
  if Value <> '' then
    AsnAdd(query, Asn(Value, ASN1_CTX1));
  decoded := SendAndReceive(Asn(query, LDAP_ASN1_EXT_REQUEST));
  result := fResultCode = LDAP_RES_SUCCESS;
  if result then
  begin
    pos := 1;
    fExtName  := AsnNext(pos, decoded, xt);
    fExtValue := AsnNext(pos, decoded, xt);
  end;
end;

function TLdapClient.DiscoverRootDN: RawUtf8;
var
  PreviousSearchScope: TLdapSearchScope;
  RootObject: TLdapResult;
  RootDnAttr: TLdapAttribute;
begin
  result := '';
  PreviousSearchScope := SearchScope;
  try
    SearchScope := SS_BaseObject;
    RootObject := SearchFirst('', '*', ['rootDomainNamingContext']);
    if Assigned(RootObject) then
    begin
      RootDnAttr := RootObject.Attributes.Find('rootDomainNamingContext');
      if Assigned(RootDnAttr) then
        result := RootDnAttr.GetReadable;
    end;
  finally
    SearchScope := PreviousSearchScope;
  end;
end;

function TLdapClient.Connected(AndBound: boolean): boolean;
begin
  result := Sock.SockConnected and fBound;
end;

function TLdapClient.GetWellKnownObjectDN(const ObjectGUID: RawUtf8): RawUtf8;
var
  RootObject: TLdapResult;
  wellKnownObjAttrs: TLdapAttribute;
  i: integer;
  SearchPrefix: RawUtf8;
begin
  result := '';
  if RootDN = '' then
    exit;
  RootObject := SearchObject(RootDN, ['wellKnownObjects']);
  if not Assigned(RootObject) then
    exit;
  wellKnownObjAttrs := RootObject.Attributes.Find('wellKnownObjects');
  if not Assigned(wellKnownObjAttrs) then
    exit;
  SearchPrefix := 'B:32:' + ObjectGUID;
  for i := 0 to wellKnownObjAttrs.Count - 1 do
    if PosEx(SearchPrefix, wellKnownObjAttrs.GetReadable(i)) = 1 then
    begin
      result := Copy(
        wellKnownObjAttrs.GetReadable(i), Length(SearchPrefix) + 2, MaxInt);
      break;
    end;
end;

end.

