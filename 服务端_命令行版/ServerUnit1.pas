unit ServerUnit1;

{$MODE objfpc}{$H+}
{$modeswitch anonymousfunctions}
interface

uses
  {$ifdef linux}
  BaseUnix,Unix,
  {$ENDIF}
  SysUtils,
  Classes,
  SyncObjs,
  Process,
  Sockets,
  {$ifdef linux}
  fpmkunit,
  {$ENDIF}
  {$IFDEF Windows}
  jwaWindows, JwaWinType,
  {$ENDIF}
  FileUtil,
  rtcTypes, rtcSystem,
  rtcDataSrv, rtcInfo,
  rtcConn, rtcHttpSrv, rtcFunction, rtcSrvModule, rtcDataCli;

type
  // 线程安全日志类
  TThreadSafeLogger = class
  private
    FCriticalSection: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Log(const Msg: string);
    procedure LogLn(const Msg: string);
    procedure LogLn2(const Msg: string);
  end;

  TServerEventHandler = class
    RtcHttpServer1: TRtcHttpServer;
    RtcDataProvider1: TRtcDataProvider;
    FLogger: TThreadSafeLogger;
  public
    constructor Create(Logger: TThreadSafeLogger);
    procedure RtcDataProvider1CheckRequest(Sender: TRtcConnection);
    procedure RtcDataProvider1DataReceived(Sender: TRtcConnection);
    procedure RtcDataProvider1DataSent(Sender: TRtcConnection);
    procedure RtcHttpServer1Connect(Sender: TRtcConnection);
    procedure RtcHttpServer1ListenStart(Sender: TRtcConnection);
    procedure RtcHttpServer1ListenStop(Sender: TRtcConnection);
  end;

  // 服务器线程类
  TServerThread = class(TThread)
  private
    FPort: String;
    FOnStatus: TGetStrProc;
    FOnError: TGetStrProc;
    FServerEventHandler: TServerEventHandler;
    FRtcHttpServer1: TRtcHttpServer;
    FRtcDataProvider1: TRtcDataProvider;
    FLibFileList: TStringList;
    FLogger: TThreadSafeLogger;
    procedure DoStatus(const Msg: string);
    procedure DoError(const Msg: string);
  protected
    procedure Execute; override;
  public
    constructor Create(const APort: String; Logger: TThreadSafeLogger; CreateSuspended: Boolean = False);
    destructor Destroy; override;
    procedure StopServer;
    property OnStatus: TGetStrProc read FOnStatus write FOnStatus;
    property OnError: TGetStrProc read FOnError write FOnError;
  end;

var
  ServerThread: TServerThread;
  eServerPort: String;
  LibFileList: TStringList;
  FileList: TStringList;
  ServerEventHandler: TServerEventHandler;
  Logger: TThreadSafeLogger;  // 全局日志器
  KeepRunning: Boolean = True;

procedure CopyLib;
procedure StartServer;
procedure StopServer;
function GetLocalIP: string;

implementation

Function GetLocalIP: string;
{$IFDEF UNIX}
const
  CGDNSADDR = '127.0.0.1';
  CGDNSPORT = 53;
var
  S: string;
  VHostAddr: TSockAddr;
  VLength: Integer;
  VInetSockAddr: TInetSockAddr;
  VSock, VError: LongInt;
  VIPBuf: array[0..255] of Char = #0;
{$ENDIF}
{$IFDEF MSWINDOWS}
type
  P_hostent = ^hostent;      //这里不管64位还是32位都必须是PAnsiChar; PHostEnt改了结构，Win64位会不正常，因此重新定义
  hostent = record
    h_name: PAnsiChar;           // official name of host
    h_aliases: PPAnsiChar;  // alias list
    h_addrtype: Smallint;             // host address type
    h_length: Smallint;               // length of address
    case Integer of
      0: (h_addr_list: PPAnsiChar); // list of addresses
      1: (h_addr: PPAnsiChar);          // address, for backward compat
    end;
var
  VWSAData: TWSAData;
  VHostEnt: P_hostent; //PHostEnt;
  VName: string;
{$ENDIF}
begin
{$IFDEF UNIX}
    VError := 0;
    FillChar(VIPBuf, SizeOf(VIPBuf), #0);
    VSock := FpSocket(AF_INET, SOCK_DGRAM, 0);
    VInetSockAddr.sin_family := AF_INET;
    VInetSockAddr.sin_port := htons(CGDNSPORT);
    VInetSockAddr.sin_addr := StrToHostAddr(CGDNSADDR);
    if (FpConnect(VSock, @VInetSockAddr, SizeOf(VInetSockAddr)) = 0) then
      try
        VLength := SizeOf(VHostAddr);
        if (FpGetSockName(VSock, @VHostAddr, @VLength) = 0) then
        begin
          S := NetAddrToStr(VHostAddr.sin_addr);
          StrPCopy(PChar(VIPBuf), S);
        end
        else
          VError := SocketError;
      finally
        if (FpClose(VSock) <> 0) then
          VError := SocketError;
      end
    else
      VError := SocketError;
    if (VError <> 0) then
      Result := '127.0.0.1'
    else
      Result := StrPas(VIPBuf);
{$ENDIF}
{$IFDEF MSWINDOWS}
{$HINTS OFF}
      WSAStartup($101, VWSAData);
{$HINTS ON}
      SetLength(VName, 255);
      GetHostName(PAnsiChar(VName), 255);
      SetLength(VName, StrLen(PAnsiChar(VName)));
      VHostEnt := P_hostent(GetHostByName(PAnsiChar(VName)));
      Result := Format('%d.%d.%d.%d', [Byte(VHostEnt^.h_addr^[0]),
          Byte(VHostEnt^.h_addr^[1]), Byte(VHostEnt^.h_addr^[2]), Byte(VHostEnt^.h_addr^[3])]);
      SetLength(VName, 0);
      WSACleanup;
{$ENDIF}
end;

function ExecCmd(ACmd, Param1, Param2, Param3, Param4: string; AResult: Tstrings): Boolean;
var
  theProcess: TProcess;
  sTmp: TStrings;
begin
  Result := False;
  if  AResult <> nil then
    AResult.Clear;
  theProcess := TProcess.Create(nil);
  theProcess.Executable := ACmd;
  if Param1 <> '' then
  theProcess.Parameters.Add(Param1);
  if Param2 <> '' then
  theProcess.Parameters.Add(Param2);
  if Param3 <> '' then
    theProcess.Parameters.Add(Param3);
  if Param4 <> '' then
    theProcess.Parameters.Add(Param4);
  theProcess.Options := theProcess.Options + [poUsePipes];
  sTmp := TStringList.Create;
  theProcess.Execute;
  repeat
    Sleep(10);
    sTmp.Clear;
    sTmp.LoadFromStream(theProcess.Output);
    AResult.AddStrings(sTmp);
  until not theProcess.Running;
  sTmp.LoadFromStream(theProcess.Output);
  AResult.AddStrings(sTmp);
  sTmp.Free;
  theProcess.WaitOnExit;

  if theProcess.ProcessID > 4 then
    Result := True;
  theProcess.Free;
  theProcess := nil;
end;

{$ifdef linux}

procedure listLibfile;
var
  Process : TProcess;
  sResult:TStringList;
  str:String;
  i:Integer;
begin
  try
    sResult:=TStringList.Create;
    ExecCmd('ldconfig', '--print-cache','','','',sResult);
    if sResult.Count > 0 then
    begin
      FileList:=TStringList.Create;
      for i:=0 to sResult.Count-1 do
      begin
        str:=sResult[i];
        str:=Copy(str,pos(') => ',str)+5,Length(str));
        if pos(') => ',sResult[i])>0 then
          FileList.Add(str);
      end;
    end;
  finally
    //sResult.SaveToFile('lib123.txt');
    sResult.Free;
  end;
end;

procedure CopyLib;
var
  s,s1,s2,s3,str,fn,n1,n2,ldlinux:String;
  gccpath:string;
  {$ifdef linux}
  OS: TOS;
  CPU: TCPU;
  {$endif}
  SourceFile:String;
  TargetFile:String;
  Info: Stat;
  aoFileList:TStringList;
  Process : TProcess;

  i,j,k,y: Integer;

  function ISLinkFile(fn:string;out RealFile:String):Boolean;
  begin
    Result:=False;
    RealFile:=fn;
    if fpLStat(fn, Info) = 0 then
    begin
      if fpS_ISLNK(Info.st_mode) then // 使用 fpS_ISLNK 宏判断是否为符号链接
      begin
        Result:=True;
        RealFile:= fpReadLink(fn) ;
      end;
    end;
  end;
begin
  listLibfile;

  //WriteLn(#13);
  Write( #27'[2K','开始拷贝lib文件到当前目录（'+LowerCase({$I %FPCTARGETCPU%})+'-'+LowerCase({$I %FPCTARGETOS%})+'）...',#13);
  {$if defined(CPU32) and defined(CPUARM)}
  SourceFile:='/usr/lib/arm-linux-gnueabihf';
  {$else}
  SourceFile:='/usr/lib/'+LowerCase({$I %FPCTARGETCPU%})+'-'+LowerCase({$I %FPCTARGETOS%})+'-gnu';
  {$endif}
  TargetFile:=''+LowerCase({$I %FPCTARGETCPU%})+'-'+LowerCase({$I %FPCTARGETOS%});
  if not DirectoryExists(TargetFile) then
      ForceDirectories(TargetFile);
  if TargetFile[Length(TargetFile)]<>'/' then
    TargetFile:=TargetFile+'/';
  if SourceFile[Length(SourceFile)]<>'/' then
    SourceFile:=SourceFile+'/';
  if not FileExists(SourceFile+'libc.so') then
  begin
    if not FileExists('/usr/lib/libc.so') then
      SourceFile:='/usr/lib/'
    else
      SourceFile:='';
  end;
  if SourceFile='' then
  begin
    //WriteLn(#13);
    Write( #27'[2K','没找到libc.so',#13);
  end
  else
  begin
    LibFileList:=TStringList.Create;
    try
      for i := 0 to FileList.Count - 1 do
      begin
        fn:=ExtractFileName(FileList[i]);
        if ISLinkFile(FileList[i],s) then
        begin//软连接文件
          if copy(s,1,1)=SetDirSeparators('/') then
            n1:=s
          else
            n1:=ExtractFilePath(FileList[i])+s;
          n2:=TargetFile+ExtractFileName(FileList[i]);
          CopyFile(n1,n2,[cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
        end
        else
          CopyFile(FileList[i],TargetFile+ExtractFileName(FileList[i]),
             [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
        LibFileList.Add(fn);
        //WriteLn(#13);
        Write( #27'[2K', 'CopyFile No.', IntToStr(i+1)+'/'+IntToStr(FileList.Count), #13);
        //writeln(IntToStr(i+1)+'/'+IntToStr(FileList.Count));
      end;

      //拷贝a文件
      try
        aoFileList:=TStringList.Create;
        FindAllFiles(aoFileList, SourceFile, '*.a;*.o', False);
        for i := 0 to aoFileList.Count - 1 do
        begin
          fn:=ExtractFileName(aoFileList[i]);
          CopyFile(aoFileList[i],TargetFile+ExtractFileName(aoFileList[i]),
             [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
          LibFileList.Add(fn);
          Write( #27'[2K', 'CopyFile No.', IntToStr(i+1)+'/'+IntToStr(aoFileList.Count), #13);
          //WriteLn(#13);
          //writeln(IntToStr(i+1)+'/'+IntToStr(aoFileList.Count));
        end;
      finally
        aoFileList.Free;
      end;
      cpu:=StringToCPU({$I %FPCTARGET%});
      os:=StringToOS({$I %FPCTARGETOS%});

      //从/usr/lib/gcc/xxx-linux-gnu/xx,如：/usr/lib/gcc/x86_64-linux-gnu/15
      //拷贝以下4个o文件
      gccpath:= GetDefaultLibGCCDir(cpu,os,s)+'/';
      if FileExists(gccpath+'crtbeginS.o') then
      begin
        LibFileList.Add('crtbeginS.o');
        CopyFile(gccpath+'crtbeginS.o',TargetFile+'crtbeginS.o',
           [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
      end;
      if FileExists(gccpath+'crtend.o') then
      begin
        LibFileList.Add('crtend.o');
        CopyFile(gccpath+'crtend.o',TargetFile+'crtend.o',
           [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
      end;
      if FileExists(gccpath+'crtendS.o') then
      begin
        LibFileList.Add('crtendS.o');
        CopyFile(gccpath+'crtendS.o',TargetFile+'crtendS.o',
           [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
      end;
      if FileExists(gccpath+'crtbegin.o') then
      begin
        LibFileList.Add('crtbegin.o');
        CopyFile(gccpath+'crtbegin.o',TargetFile+'crtbegin.o',
           [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
      end;

      if FileExists(SourceFile+'libQt5Pas.so.1') then
      begin
        LibFileList.Add('libQt5Pas.so');
        CopyFile(SourceFile+'libQt5Pas.so.1',TargetFile+'libQt5Pas.so',
           [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
      end;

      //修改libc.so文件
      if FileExists(SourceFile+'libc.so') then
      begin
        FileList.LoadFromFile(SourceFile+'libc.so');
        for i:=0 to  FileList.Count-1 do
        begin
          k:=pos('libc.so',FileList[i]);
          if k>0 then
          begin
             s1:='';
             str:=FileList[i];
             for j:=k to length(str)-1 do
             begin
                if str[j]<>' ' then
                  s1:=s1+str[j]
                else
                  break;
             end;
             k:=pos('libc_nonshared.a',FileList[i]);
             if k>0 then
               s2:='libc_nonshared.a';

             k:=pos('ld-linux-',FileList[i]);
             ldlinux:=copy(FileList[i],pos('AS_NEEDED',FileList[i])+10,length(FileList[i]));
             ldlinux:=ldlinux.Replace(' ','',[rfReplaceAll]);
             ldlinux:=ldlinux.Replace('(','',[rfReplaceAll]);
             ldlinux:=ldlinux.Replace(')','',[rfReplaceAll]);
             CopyFile(ldlinux,TargetFile+ExtractFileName(ldlinux),
                [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
             s3:='';
             str:=FileList[i];
             for j:=k to length(str)-1 do
             begin
                if str[j]<>' ' then
                  s3:=s3+str[j]
                else
                  break;
             end;
          str:='GROUP ( '+s1+' '+s2+'  AS_NEEDED ( '+s3+' ))';
          FileList[i]:=str;
          end;
        end;
        FileList.SaveToFile(TargetFile+'/libc.so');
        LibFileList.Add('libc.so');
        //libc.so修改完成
        try
          Process := TProcess.Create(nil);
          Process.CurrentDirectory := SetDirSeparators(Extractfilepath(Paramstr(0))+TargetFile+'/');
          Process.Executable := '/bin/sh';
          Process.Parameters.Add('-c');
          Process.Parameters.Add('uname -svmro > actual_library_version_info.txt');
          Process.ShowWindow := swoHIDE;
          Process.Execute;
          LibFileList.Add('actual_library_version_info.txt');
        finally
          Process.Free;
        end;
        //WriteLn(#13);
        Write( #27'[2K','lib文件拷贝完成',#13);
      end;
    finally
       FileList.Free;
    end;
  end;
end;

procedure CopyLibAllFiles;
var
  s,s1,s2,s3,str,fn,n1,n2,ldlinux:String;
  gccpath:string;
  {$ifdef linux}
  OS: TOS;
  CPU: TCPU;
  {$endif}
  SourceFile:String;
  TargetFile:String;
  //lnkfile:TStringList;
  Info: Stat;
  Process : TProcess;

  FileList: TStringList;
  i,j,k,y: Integer;

  function ISLinkFile(fn:string;out RealFile:String):Boolean;
  begin
    Result:=False;
    RealFile:=fn;
    if fpLStat(fn, Info) = 0 then
    begin
      if fpS_ISLNK(Info.st_mode) then // 使用 fpS_ISLNK 宏判断是否为符号链接
      begin
        Result:=True;
        RealFile:= fpReadLink(fn) ;
      end;
    end;
  end;
begin
  WriteLn(#13);
  writeln('开始拷贝lib文件到当前目录（'+LowerCase({$I %FPCTARGETCPU%})+'-'+LowerCase({$I %FPCTARGETOS%})+'）...');
  {$if defined(CPU32) and defined(CPUARM)}
  SourceFile:='/usr/lib/arm-linux-gnueabihf';
  {$else}
  SourceFile:='/usr/lib/'+LowerCase({$I %FPCTARGETCPU%})+'-'+LowerCase({$I %FPCTARGETOS%})+'-gnu';
  {$endif}
  TargetFile:=''+LowerCase({$I %FPCTARGETCPU%})+'-'+LowerCase({$I %FPCTARGETOS%});
  if not DirectoryExists(TargetFile) then
      ForceDirectories(TargetFile);
  if TargetFile[Length(TargetFile)]<>'/' then
    TargetFile:=TargetFile+'/';
  if SourceFile[Length(SourceFile)]<>'/' then
    SourceFile:=SourceFile+'/';
  if not FileExists(SourceFile+'libc.so') then
  begin
    if not FileExists('/usr/lib/libc.so') then
      SourceFile:='/usr/lib/'
    else
      SourceFile:='';
  end;
  if SourceFile='' then
  begin
    WriteLn(#13);
    writeln('没找到libc.so');
  end
  else
  begin
    LibFileList:=TStringList.Create;
    FileList := TStringList.Create;
    try
      // 获取所有文件
      FindAllFiles(FileList, SourceFile, '*.*', False);

      for i := 0 to FileList.Count - 1 do
      begin
        fn:=ExtractFileName(FileList[i]);
        if ISLinkFile(FileList[i],s) then
        begin//软连接文件
          if copy(s,1,1)=SetDirSeparators('/') then
             n1:=s
          else
            n1:=ExtractFilePath(FileList[i])+s;
          n2:=TargetFile+ExtractFileName(FileList[i]);
          //if not FileExists(ExtractFileName(n1)) then
          //  CopyFile(n1,TargetFile+ExtractFileName(n1),[cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
         CopyFile(n1,n2,[cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
          //lnkfile:=TStringList.Create;
          //lnkfile.Add('GROUP ( '+ExtractFileName(n1+' )'));
          //lnkfile.SaveToFile(n2);
          //lnkfile.Free;
        end
        else
          CopyFile(FileList[i],TargetFile+ExtractFileName(s),
           [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
        LibFileList.Add(fn);
        //GotoXY(1, y);
        WriteLn(#13);
        writeln(IntToStr(i+1)+'/'+IntToStr(FileList.Count));
      end;

      cpu:=StringToCPU({$I %FPCTARGET%});
      os:=StringToOS({$I %FPCTARGETOS%});

      //从/usr/lib/gcc/xxx-linux-gnu/xx,如：/usr/lib/gcc/x86_64-linux-gnu/15
      //拷贝以下4个o文件
      gccpath:= GetDefaultLibGCCDir(cpu,os,s)+'/';
      if FileExists(gccpath+'crtbeginS.o') then
      begin
        LibFileList.Add('crtbeginS.o');
        CopyFile(gccpath+'crtbeginS.o',TargetFile+'crtbeginS.o',
           [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
      end;
      if FileExists(gccpath+'crtend.o') then
      begin
        LibFileList.Add('crtend.o');
        CopyFile(gccpath+'crtend.o',TargetFile+'crtend.o',
           [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
      end;
      if FileExists(gccpath+'crtendS.o') then
      begin
        LibFileList.Add('crtendS.o');
        CopyFile(gccpath+'crtendS.o',TargetFile+'crtendS.o',
           [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
      end;
      if FileExists(gccpath+'crtbegin.o') then
      begin
        LibFileList.Add('crtbegin.o');
        CopyFile(gccpath+'crtbegin.o',TargetFile+'crtbegin.o',
           [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
      end;

      //修改libc.so文件
      if FileExists(SourceFile+'libc.so') then
      begin
        FileList.LoadFromFile(SourceFile+'libc.so');
        for i:=0 to  FileList.Count-1 do
        begin
          k:=pos('libc.so',FileList[i]);
          if k>0 then
          begin
             s1:='';
             str:=FileList[i];
             for j:=k to length(str)-1 do
             begin
                if str[j]<>' ' then
                  s1:=s1+str[j]
                else
                  break;
             end;
             k:=pos('libc_nonshared.a',FileList[i]);
             if k>0 then
               s2:='libc_nonshared.a';

             k:=pos('ld-linux-',FileList[i]);
             ldlinux:=copy(FileList[i],pos('AS_NEEDED',FileList[i])+10,length(FileList[i]));
             ldlinux:=ldlinux.Replace(' ','',[rfReplaceAll]);
             ldlinux:=ldlinux.Replace('(','',[rfReplaceAll]);
             ldlinux:=ldlinux.Replace(')','',[rfReplaceAll]);
             CopyFile(ldlinux,TargetFile+ExtractFileName(ldlinux),
                [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
             s3:='';
             str:=FileList[i];
             for j:=k to length(str)-1 do
             begin
                if str[j]<>' ' then
                  s3:=s3+str[j]
                else
                  break;
             end;
          str:='GROUP ( '+s1+' '+s2+'  AS_NEEDED ( '+s3+' ))';
          FileList[i]:=str;
          end;
        end;
        FileList.SaveToFile(TargetFile+'/libc.so');
        LibFileList.Add('libc.so');
       //libc.so修改完成
        try
          Process := TProcess.Create(nil);
          Process.CurrentDirectory := SetDirSeparators(Extractfilepath(Paramstr(0))+TargetFile+'/');
          Process.Executable := '/bin/sh';
          Process.Parameters.Add('-c');
          Process.Parameters.Add('uname -svmro > actual_library_version_info.txt');
          Process.ShowWindow := swoHIDE;
          Process.Execute;
          LibFileList.Add('actual_library_version_info.txt');
        finally
          Process.Free;
        end;
        WriteLn(#13);
        writeln('lib文件拷贝完成');
      end;
    finally
       FileList.Free;
    end;
  end;
end;
{$endif}

{$IFDEF LINUX}
function CheckPortAvailable(Port: Integer): Boolean;
var
  sock: LongInt;
  addr: TInetSockAddr;
begin
  Result := False;

  sock := fpSocket(AF_INET, SOCK_STREAM, 0);
  if sock < 0 then Exit;

  try
    FillChar(addr, SizeOf(addr), 0);
    addr.sin_family := AF_INET;
    addr.sin_port := htons(Port);
    addr.sin_addr.s_addr := htonl(INADDR_ANY);

    if fpBind(sock, @addr, SizeOf(addr)) = 0 then
      Result := True;
  finally
    fpClose(sock);
  end;
end;
{$ENDIF}

{ TThreadSafeLogger }

constructor TThreadSafeLogger.Create;
begin
  inherited Create;
  FCriticalSection := TCriticalSection.Create;
end;

destructor TThreadSafeLogger.Destroy;
begin
  FCriticalSection.Free;
  inherited Destroy;
end;

procedure TThreadSafeLogger.Log(const Msg: string);
begin
  FCriticalSection.Enter;
  try
    WriteLn(#13);
    WriteLn(Msg);
    Flush(Output);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TThreadSafeLogger.LogLn(const Msg: string);
begin
  FCriticalSection.Enter;
  try
    Writeln(#13);
    Write( #27'[2K',Msg, #13);
    //WriteLn(Msg);
    Flush(Output);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TThreadSafeLogger.LogLn2(const Msg: string);
begin
  FCriticalSection.Enter;
  try
    Write( #27'[2K',Msg, #13);
    //WriteLn(Msg);
    Flush(Output);
  finally
    FCriticalSection.Leave;
  end;
end;

{ TServerThread }

constructor TServerThread.Create(const APort: String; Logger: TThreadSafeLogger; CreateSuspended: Boolean);
begin
  inherited Create(CreateSuspended);
  FPort := APort;
  FLogger := Logger;
  FreeOnTerminate := False;
end;

destructor TServerThread.Destroy;
begin
  StopServer;
  inherited Destroy;
end;

procedure TServerThread.DoStatus(const Msg: string);
begin
  if Assigned(FOnStatus) then
    FOnStatus(Msg);
end;

procedure TServerThread.DoError(const Msg: string);
begin
  if Assigned(FOnError) then
    FOnError(Msg);
end;

procedure TServerThread.StopServer;
begin
  // 停止服务器
  if Assigned(FRtcHttpServer1) then
  begin
    if FRtcHttpServer1.isListening then
    begin
      FLogger.LogLn('正在停止服务器监听...');
      FRtcHttpServer1.StopListen;
    end;
  end;

  // 终止线程
  Terminate;
end;

procedure TServerThread.Execute;
var
  Port: Integer;
begin
  try
    FLogger.LogLn('QF远程调试服务器初始化...');

    // 创建事件处理器
    FServerEventHandler := TServerEventHandler.Create(FLogger);
    //FLogger.LogLn('事件处理器已创建');

    // 创建RTC服务器
    FRtcHttpServer1 := TRtcHttpServer.Create(nil);
    //FLogger.LogLn('RTC HTTP服务器已创建');

    // 创建数据提供者
    FRtcDataProvider1 := TRtcDataProvider.Create(nil);
    //FLogger.LogLn('RTC数据提供者已创建');
    FLogger.LogLn('QF远程调试服务器完成初始化.');

    // 设置服务器属性
    with FRtcHttpServer1 do
    begin
      ServerAddr := '0.0.0.0';  // 监听所有网络接口
      ServerPort := FPort;

      // 启用多线程
      MultiThreaded := True;

      // 设置超时
      Timeout.AfterConnecting := 60000;
      Timeout.AfterDataReceived := 30000;
      Timeout.AfterDataSend := 30000;

      // 设置其他重要属性
      MaxRequestSize := 1024 * 1024 * 100; // 最大100MB请求
      MaxHeaderSize := 65536;

      FLogger.LogLn('服务器配置完成:');
      FLogger.LogLn('  监听地址: ' + ServerAddr);
      FLogger.LogLn('  监听端口: ' + ServerPort);
      FLogger.LogLn('  多线程: ' + BoolToStr(MultiThreaded, True));
    end;

    // 设置数据提供者
    FRtcDataProvider1.Server := FRtcHttpServer1;

    // 关联事件处理程序
    FRtcDataProvider1.OnCheckRequest := @FServerEventHandler.RtcDataProvider1CheckRequest;
    FRtcDataProvider1.OnDataReceived := @FServerEventHandler.RtcDataProvider1DataReceived;
    FRtcDataProvider1.OnDataSent := @FServerEventHandler.RtcDataProvider1DataSent;

    FRtcHttpServer1.OnConnect := @FServerEventHandler.RtcHttpServer1Connect;
    FRtcHttpServer1.OnListenStart := @FServerEventHandler.RtcHttpServer1ListenStart;
    FRtcHttpServer1.OnListenStop := @FServerEventHandler.RtcHttpServer1ListenStop;


    // 检查端口是否可用
    {$IFDEF LINUX}
    sleep(1000);
    Port := StrToIntDef(FPort, 8080);
    if not CheckPortAvailable(Port) then
    begin
      FLogger.LogLn('端口 ' + FPort + ' 可能已被占用');
      FLogger.LogLn('尝试使用端口: 8088');
      FPort := '8088';
      eServerPort:=FPort;
      FRtcHttpServer1.ServerPort := FPort;
    end;
    {$ENDIF}

    // 启动服务器
    try
      FLogger.LogLn('正在启动服务器监听...');
      FRtcHttpServer1.Listen;

      // 等待服务器完全启动
      Sleep(500);

      if FRtcHttpServer1.isListening then
      begin
        FLogger.LogLn('=======================================');
        FLogger.LogLn('服务器启动成功！');
        FLogger.LogLn('服务地址: http://' + GetLocalIP + ':' + FPort);
        FLogger.LogLn('本地地址: http://127.0.0.1:' + FPort);
        FLogger.LogLn('=======================================');
        FLogger.LogLn('');
      end
      else
      begin
        DoError('服务器启动失败！');
        Exit;
      end;

    except
      on E: Exception do
      begin
        DoError('监听端口失败: ' + E.Message);
        FLogger.LogLn('尝试使用端口: 8088');

        // 尝试使用备用端口
        try
          FRtcHttpServer1.ServerPort := '8088';
          FRtcHttpServer1.Listen;
          Sleep(500);

          if FRtcHttpServer1.isListening then
          begin
            FPort := '8088';
            FLogger.LogLn('=======================================');
            FLogger.LogLn('服务器使用备用端口启动成功！');
            FLogger.LogLn('服务地址: http://' + GetLocalIP + ':' + FPort);
            FLogger.LogLn('=======================================');
          end
          else
          begin
            DoError('备用端口也失败');
            Exit;
          end;
        except
          on E2: Exception do
          begin
            DoError('备用端口也失败: ' + E2.Message);
            Exit;
          end;
        end;
      end;
    end;

    // 主循环 - 保持线程运行
    while not Terminated do
    begin
      Sleep(1000);
    end;

    // 清理
    FLogger.LogLn('正在清理服务器资源...');

    if Assigned(FRtcHttpServer1) then
    begin
      if FRtcHttpServer1.isListening then
        FRtcHttpServer1.StopListen;
      FreeAndNil(FRtcHttpServer1);
    end;

    if Assigned(FRtcDataProvider1) then
      FreeAndNil(FRtcDataProvider1);

    if Assigned(FServerEventHandler) then
      FreeAndNil(FServerEventHandler);

    if Assigned(FLibFileList) then
      FreeAndNil(FLibFileList);

    FLogger.LogLn('服务器已停止');

  except
    on E: Exception do
    begin
      FLogger.LogLn('服务器线程异常: ' + E.Message);
    end;
  end;
end;

procedure StartServer;
begin
  // 如果服务器已经在运行，先停止它
  StopServer;

  // 创建并启动服务器线程
  ServerThread := TServerThread.Create(eServerPort, Logger, True);

  // 设置事件处理程序
  ServerThread.OnStatus :=
    procedure(const Msg: string)
    begin
      Logger.LogLn('[状态] ' + Msg);
    end;

  ServerThread.OnError :=
    procedure(const Msg: string)
    begin
      Logger.LogLn('[错误] ' + Msg);
    end;

  // 启动线程
  ServerThread.Start;
end;


procedure StopServer;
begin
  if Assigned(ServerThread) then
  begin
    WriteLn(#13);
    WriteLn('正在停止服务器...');
    ServerThread.StopServer;

    // 等待线程结束
    ServerThread.WaitFor;

    FreeAndNil(ServerThread);
    WriteLn(#13);
    WriteLn('服务器已停止');
  end;
end;

constructor TServerEventHandler.Create(Logger: TThreadSafeLogger);
begin
  inherited Create;
  FLogger := Logger;
end;

procedure TServerEventHandler.RtcHttpServer1Connect(Sender: TRtcConnection);
begin
  with TRtcDataServer(Sender) do
  begin
    FLogger.LogLn2(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) +
            ' - 客户端连接: ' + PeerAddr + ':' + PeerPort);
  end;
end;

procedure TServerEventHandler.RtcHttpServer1ListenStart(Sender: TRtcConnection);
begin
  if Assigned(FLogger) then
    FLogger.LogLn(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' - 服务器开始监听');
end;

procedure TServerEventHandler.RtcHttpServer1ListenStop(Sender: TRtcConnection);
begin
  if Assigned(FLogger) then
    FLogger.LogLn(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' - 服务器停止监听');
end;

procedure TServerEventHandler.RtcDataProvider1CheckRequest(Sender: TRtcConnection);
var
  fileName: string;
begin
  with TRtcDataServer(Sender) do
  begin
    // 处理文件上传请求
    if (Request.Method = 'PUT') and (UpperCase(Request.FileName) = '/DEBUG') and
      (Request.Query['file'] <> '') then
    begin
      FLogger.LogLn2(Request.Query['file']+'开始上传。');
      Request.Info.asText['file'] :=
        'RemoteDebugFile\' + Utf8Decode(URL_Decode(Request.Query['file']));
      Request.Info.AsString['request_type'] := 'debug';
      Accept;
    end
    else
    // 处理文件上传请求
    if (Request.Method = 'PUT') and (UpperCase(Request.FileName) = '/UPLOAD') and
      (Request.Query['file'] <> '') then
    begin
      FLogger.LogLn2(Request.Query['file']+'开始上传。');
      Request.Info.asText['file'] :=
        'RemoteDebugFile\' + Utf8Decode(URL_Decode(Request.Query['file']));
      Request.Info.AsString['request_type'] := 'upload';
      Accept;
    end
    else
    // 处理文件下载请求
    if (Request.Method = 'GET') and (UpperCase(Request.FileName) = '/DOWNLOAD') and
      (Request.Query['file'] <> '') then
    begin
      if copy(URL_Decode(UTF8Decode(Request.Query['file'])),1,3)='///' then
      begin
        fileName:=URL_Decode(UTF8Decode(Request.Query['file']));
        fileName:= fileName.Replace('///','',[]);
        fileName:= SetDirSeparators(Extractfilepath(ParamStr(0))+fileName);
      end
      else
        fileName := Utf8Decode(URL_Decode(SetDirSeparators(Extractfilepath(ParamStr(0))+'download\'+Request.Query['file'])));
      if FileExists(fileName) then
      begin
        //Write( #27'[2K','下载:'+ExtractFileName(fileName), #13);
        //FLogger.LogLn2('下载:'+ExtractFileName(fileName));
        Request.Info.asText['file'] := fileName;
        Request.Info.AsString['request_type'] := 'download';
        Request.Info.asLargeInt['file_size'] := File_Size(fileName);
        Request.Info.asLargeInt['bytes_sent'] := 0;  // 初始化已发送字节数
        Accept;
      end
      else
      begin
        Response.Status(404, 'File Not Found');
        Write('File not found: ' + fileName);
      end;
    end
    // 处理文件下载请求
    else
    if (Request.Method = 'GET') and (UpperCase(Request.FileName) = '/DOWNLOADLIBLIST') and
      (Request.Query['file'] <> '') then
    begin
      {$ifdef linux}
      CopyLib;
      LibFileList.SaveToFile(SetDirSeparators(Extractfilepath(ParamStr(0))+'liblist.txt'));

      fileName :=Utf8Decode(URL_Decode(SetDirSeparators(Extractfilepath(ParamStr(0))+'liblist.txt')));
      if FileExists(fileName) then
      begin
        Request.Info.asText['file'] := fileName;
        Request.Query['file']:='liblist.txt';
        Request.Info.AsString['request_type'] := 'downloadliblist';
        Request.Info.asLargeInt['file_size'] := File_Size(fileName);
        Request.Info.asLargeInt['bytes_sent'] := 0;  // 初始化已发送字节数
        Accept;
      end
      else
      begin
        Response.Status(404, 'File Not Found');
        Write('File not found: ' + fileName);
      end;
      {$endif}
    end;
  end;
end;

procedure TServerEventHandler.RtcDataProvider1DataReceived(Sender: TRtcConnection);
var
  bSize,libfileno: int64;
  s: RtcString;
  f, F1: string;
  Process: TProcess;
  sh: TStringList;
  requestType: string;
  fileName: string;
  fileSize: int64;
  outs: int64;
  bytesToSend: int64;
  bufferSize: integer;
  fileStream: TFileStream;

  procedure KillProcessByName(ProcessName: string);
  var
    Proc: TProcess;
  begin
    Proc := TProcess.Create(nil);
    try
      Proc.Executable := 'pkill';
      //Proc.Parameters.Add('-f');  // 根据完整命令行匹配
      Proc.Parameters.Add('gdbserver');
      Proc.Options := [poWaitOnExit];
      Proc.Execute;
    finally
      Proc.Free;
    end;
  end;

begin
  with TRtcDataServer(Sender) do
  begin
    requestType := Request.Info.AsString['request_type'];
    if requestType = 'deletefile' then
    begin
      if not DirectoryExists('RemoteDebugFile') then
        CreateDir('RemoteDebugFile');
      KillProcessByName('gdbserver');
      DeleteFile(SetDirSeparators(Extractfilepath(ParamStr(0)) +
        'RemoteDebugFile\' + Request.Info.asText['file']));
      DeleteFile(SetDirSeparators(Extractfilepath(ParamStr(0)) +
        'RemoteDebugFile\run.sh'));
    end
    else
    if requestType = 'upload' then
    begin
      if Request.Started then
      begin
       if not DirectoryExists('upload') then
          CreateDir('upload');
      end;
      s := Read;
      f1 := Request.Query['file'];
      f := SetDirSeparators(Extractfilepath(ParamStr(0))+'upload/'+Request.Query['file']);
      Write_File(f, s, Request.ContentIn - length(s));
      //Write_File(Request.Info.asText['file'], s, Request.ContentIn - length(s));

      if Request.Complete then
      begin
        Response.Status(200, 'OK'); // Set response status to a standard "OK"
        Write('upload done!');
        FLogger.LogLn2(Request.Query['file']+'上传成功。');
        {$ifdef linux}
        fpchmod(f,493); //设置执行权限
        {$endif}
      end;
    end
    else
    if requestType = 'debug' then
    begin
      if Request.Started then
      begin
        if not DirectoryExists('RemoteDebugFile') then
          CreateDir('RemoteDebugFile');
        KillProcessByName('gdbserver');
        DeleteFile(SetDirSeparators(Extractfilepath(ParamStr(0)) +
          'RemoteDebugFile\' + Request.Info.asText['file']));
        DeleteFile(SetDirSeparators(Extractfilepath(ParamStr(0)) +
          'RemoteDebugFile\run.sh'));
      end;
      s := Read;
      f1 := Request.Query['file'];
      f := SetDirSeparators(Extractfilepath(ParamStr(0))+'RemoteDebugFile/'+Request.Query['file']);
      Write_File(f, s, Request.ContentIn - length(s));
      //Write_File(Request.Info.asText['file'], s, Request.ContentIn - length(s));

      if Request.Complete then
      begin
        Response.Status(200, 'OK'); // Set response status to a standard "OK"
        Write('upload done!');
        {$ifdef linux}
        FLogger.LogLn2(Request.Query['file']+'上传成功。');
        KillProcessByName('gdbserver');
        fpchmod(f,493); //设置执行权限
        KillProcessByName('gdbserver');
        //上传完成后执行上传和程序：
        sh:=TStringList.Create;
        sh.Add('gdbserver :2345 '+f1);
        sh.SaveToFile(SetDirSeparators(Extractfilepath(Paramstr(0))+'RemoteDebugFile/run.sh'));

        fpchmod(SetDirSeparators(Extractfilepath(Paramstr(0))+'RemoteDebugFile/run.sh'),493); //run.sh设置执行权限

        Process := TProcess.Create(nil);
        Process.CurrentDirectory := SetDirSeparators(Extractfilepath(Paramstr(0))+'RemoteDebugFile/');
        Process.Executable := 'sh';
        Process.Parameters.Add('run.sh');
        Process.ShowWindow :=swoShow;// swoHIDE;
        Process.Execute;
        {$endif}
      end;
    end
    else
    if requestType = 'downloadliblist' then
    begin
      {$ifdef linux}
      fileName :=SetDirSeparators(Extractfilepath(ParamStr(0)) + 'liblist.txt');
      fileSize := File_Size(fileName);
      Request.Info.asLargeInt['file_size']:=fileSize;
      Request.Info.asText['file']:=fileName;

      if Request.Started then
      begin
        Response.ContentLength := fileSize;
        WriteHeader; //文件下载一定要加这行才会触发DataSent
      end;
      fileName := Request.Info.asText['file'];
      fileSize := Request.Info.asLargeInt['file_size'];

      if fileSize > 0 then
      begin
        bufferSize := 65536; // 64KB 每块
        bytesToSend := fileSize;
        if bytesToSend > bufferSize then
          bytesToSend := bufferSize;

        // 读取并发送第一块数据,后由DataSent继续发送剩余部分
        s := Read_File(fileName, 0, bytesToSend);
        if s <> '' then
        begin
          Write(s);
          Request.Info.asLargeInt['bytes_sent'] := bytesToSend;
        end;
      end;
      {$endif}
    end
    else
    if requestType = 'download' then
    begin
      // 文件下载处理）
      if not DirectoryExists('download') then
        CreateDir('download');

      fileName :=SetDirSeparators(Extractfilepath(ParamStr(0)) + 'download\' +
        Request.Info.asText['file']);
      fileSize := Request.Info.asLargeInt['file_size'];

      if Request.Started then
      begin
        Response.ContentLength := fileSize;
        WriteHeader; //文件下载一定要加这行才会触发DataSent
      end;
      fileName := Request.Info.asText['file'];
      fileSize := Request.Info.asLargeInt['file_size'];

      if fileSize > 0 then
      begin
        bufferSize := 65536; // 64KB 每块
        bytesToSend := fileSize;
        if bytesToSend > bufferSize then
          bytesToSend := bufferSize;

        // 读取并发送第一块数据,后由DataSent继续发送剩余部分
        s := Read_File(fileName, 0, bytesToSend);
        if s <> '' then
        begin
          Write(s);
          Request.Info.asLargeInt['bytes_sent'] := bytesToSend;
        end;
      end;
    end;
  end;
end;

procedure TServerEventHandler.RtcDataProvider1DataSent(Sender: TRtcConnection);
var
  s: RtcString;
  requestType: string;
  fileName: string;
  fileSize: int64;
  bytesSent: int64;
  bytesToSend: int64;
  bufferSize: integer;
  percent: Integer;
begin
  with TRtcDataServer(Sender) do
  begin
    requestType := Request.Info.AsString['request_type'];

    if requestType = 'download' then
    begin
      fileName := Request.Info.asText['file'];
      fileSize := Request.Info.asLargeInt['file_size'];
      bytesSent := Request.Info.asLargeInt['bytes_sent'];

      // 计算当前进度百分比
      percent := (bytesSent * 100) div fileSize;

      // 只在整十百分比（10%, 20%, ... 100%）时显示进度
      if (percent mod 10 = 0) and (percent > Request.Info.asInteger['last_reported_percent']) then
      begin
        Request.Info.asInteger['last_reported_percent'] := percent;
        FLogger.LogLn2('在下载:'+Format('%s: %d%% (%.1f/%.1f MB)', [
          ExtractFileName(fileName),
          percent,
          bytesSent / 1024 / 1024,
          fileSize / 1024 / 1024
        ]));
      end;

      // 如果还有数据需要发送
      if bytesSent < fileSize then
      begin
        bufferSize := 65536; // 64KB 每块
        bytesToSend := fileSize - bytesSent;
        if bytesToSend > bufferSize then
          bytesToSend := bufferSize;

        // 读取文件数据并发送
        s := Read_File(fileName, bytesSent, bytesToSend);
        if s <> '' then
        begin
          Write(s);
          Request.Info.asLargeInt['bytes_sent'] := bytesSent + bytesToSend;
        end;
      end;

      // 如果发送完成
      if Request.Info.asLargeInt['bytes_sent'] >= fileSize then
      begin
        // 显示完成信息
        FLogger.LogLn2(Format('%s: 下载完成 (%.1f MB)', [
          ExtractFileName(fileName),
          fileSize / 1024 / 1024
        ]));
        // 文件发送完成
        Request.Info.AsString['request_type'] := '';  // 清除请求类型
      end;
    end
    else
    if requestType = 'downloadliblist' then
    begin
      fileName := Request.Info.asText['file'];
      fileSize := Request.Info.asLargeInt['file_size'];
      bytesSent := Request.Info.asLargeInt['bytes_sent'];

      // 如果还有数据需要发送
      if bytesSent < fileSize then
      begin
        bufferSize := 65536; // 64KB 每块
        bytesToSend := fileSize - bytesSent;
        if bytesToSend > bufferSize then
          bytesToSend := bufferSize;

        // 读取文件数据并发送
        s := Read_File(fileName, bytesSent, bytesToSend);
        if s <> '' then
        begin
          Write(s);
          Request.Info.asLargeInt['bytes_sent'] := bytesSent + bytesToSend;
        end;
      end;

      // 如果发送完成
      if Request.Info.asLargeInt['bytes_sent'] >= fileSize then
      begin
        // 文件发送完成
        Request.Info.AsString['request_type'] := '';  // 清除请求类型
      end;
    end;
  end
end;

initialization
Logger := TThreadSafeLogger.Create;
ServerThread := nil;

finalization
  // 确保服务器停止
StopServer;
Logger.Free;

end.
