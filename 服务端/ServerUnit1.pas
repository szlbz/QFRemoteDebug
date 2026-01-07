unit ServerUnit1;

{$MODE objfpc}{$H+}

interface

uses
  LCLIntf, LCLType, LMessages, Messages, SysUtils, Classes,
  Graphics, Controls, Forms,
  IniFiles,
  Process,
  Dialogs, StdCtrls, ExtCtrls,
  Sockets,
  {$ifdef linux}
  BaseUnix,Unix,
  cthreads,
  fpmkunit,
  {$ENDIF}
  {$IFDEF Windows}
    jwaWindows, JwaWinType,
  {$ENDIF}
  crt,
  LazUtils,
  FileUtil,
  rtcTypes, rtcSystem,
  rtcDataSrv, rtcInfo,
  rtcConn, rtcHttpSrv, rtcFunction, rtcSrvModule, rtcDataCli;

type

  { TForm2 }

  TForm2 = class(TForm)
    Label2: TLabel;
    Memo1: TMemo;
    Panel1: TPanel;
    Timer1: TTimer;
    RtcHttpServer1: TRtcHttpServer;
    RtcDataProvider1: TRtcDataProvider;
    Label1: TLabel;
    eServerPort: TEdit;
    btnListen: TButton;
    procedure btnListenClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure RtcDataProvider1DataSent(Sender: TRtcConnection);
    procedure Timer1Timer(Sender: TObject);
    procedure RtcHttpServer1Connect(Sender: TRtcConnection);
    procedure RtcHttpServer1ListenStart(Sender: TRtcConnection);
    procedure RtcHttpServer1ListenStop(Sender: TRtcConnection);
    procedure RtcDataProvider1CheckRequest(Sender: TRtcConnection);
    procedure RtcDataProvider1DataReceived(Sender: TRtcConnection);
  private
    { Private declarations }
    LibFileList:TStringList;
    {$ifdef linux}
    procedure CopyLib;
    {$endif}
  public
    { Public declarations }
  end;

var
  Form2: TForm2;

implementation


Function GetLocalIP: string;
{$IFDEF UNIX}
const
  CGDNSADDR = '8.8.8.8';
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

{$ifdef linux}
function FindProcess(AFileName, ACmdLine: string): Integer;
var
  Info: TSearchRec;
  pid: Integer;
  f: TextFile;
  fcmd: File;
  line, sTmp, status: string;
  buffer: array [0..4095] of AnsiChar;
  bytesRead, i, cmdPos: Integer;
begin
  Result := 0;
  if FindFirst('/proc/*', faDirectory, Info) = 0 then
  begin
    repeat
      if TryStrToInt(Info.Name, pid) then
      begin
        // 读取进程cmdline
        if FileExists('/proc/' + Info.Name + '/status') then
        begin
          AssignFile(f, '/proc/' + Info.Name + '/status');
          Reset(f);
          ReadLn(f, line);
          if Pos('name:', Lowercase(line)) = 1 then
            Delete(line, 1, Pos(#9, line));
          status := '';
          while not eof(f) do
          begin
            Readln(f, sTmp);
            if Pos('state:', Lowercase(sTmp)) = 1 then
            begin
              Delete(sTmp, 1, Pos(#9, sTmp));
              status := sTmp;
              Break;
            end;
          end;
          CloseFile(f);
          if status <> '' then
            if status[1] in ['Z', 'X'] then
              Continue;

          if (UpperCase(line)=UpperCase(AFileName)) or ((UpperCase(ExtractFileName(AFileName))) = UpperCase(line)) then
          begin
            if ACmdLine = '' then
            begin
              Result := pid;
              Break
            end
            else begin
              try
                line := '';
                { 非只读模式blockread永远读出来是空 }
                Assign(fcmd, '/proc/' + Info.Name + '/cmdline');
                FileMode := 0;  // 设置为只读模式
                Reset(fcmd, 1);
                try
                  BlockRead(fcmd, buffer, SizeOf(buffer), bytesRead);
                  for i := 0 to bytesRead - 1 do
                  begin
                    if buffer[i] = #0 then
                    begin
                      cmdPos := i + 1;
                      Break
                    end
                    else
                      buffer[i] := ' ';
                  end;
                  for i := cmdPos to bytesRead - 1 do
                  begin
                    if buffer[i] = #0 then
                      buffer[i] := ' '; // 替换null字符为空格
                  end;
                  SetString(line, buffer, bytesRead);
                  line := Trim(line);
                finally
                  CloseFile(fcmd);
                end;
              except
                //
              end;
              if ACmdLine = line then
              begin
                Result := pid;
                Break
              end;
            end;
          end;
        end;
      end;
    until FindNext(Info) <> 0;
    FindClose(Info);
  end;
end;
{$else}
function FindProcess(AFileName, ACmdLine: string): Integer;
var
  ContinueLoop: BOOL;//用于判断进程遍历是否完成
  FSnapshotHandle: THandle;
  FProcessEntry64: {$IFDEF WIN32}PPROCESSENTRY32{$ELSE}PPROCESSENTRY64{$ENDIF};
  FProcessEntry32: TPROCESSENTRY32;
begin
  Result := 0;
  FSnapshotHandle := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  FProcessEntry32.dwSize := Sizeof({$IFDEF WIN32}TPROCESSENTRY32{$ELSE}TPROCESSENTRY64{$ENDIF});
  ContinueLoop := Process32First(FSnapshotHandle, FProcessEntry32);
  FProcessEntry64 := {$IFDEF WIN32}PPROCESSENTRY32{$ELSE}PPROCESSENTRY64{$ENDIF}(@FProcessEntry32);
  while integer(ContinueLoop) <> 0 do
  begin
    if ((UpperCase(ExtractFileName(FProcessEntry64^.szExeFile)) = UpperCase(AFileName))
     or (UpperCase(FProcessEntry64^.szExeFile) = UpperCase(AFileName))) then
    begin
      EnableDebug(True);
      if (ACmdLine = '') or (Pos(ACmdLine, Process_CmdLine(FProcessEntry32.th32ProcessID))> 0) then
      begin
        Result := FProcessEntry64^.th32ProcessID;
        Break;
      end;
      EnableDebug(False);
    end;
    ContinueLoop := Process32Next(FSnapshotHandle, FProcessEntry32);
  end;
  CloseHandle(FSnapshotHandle);
end;
{$endif}

{$ifdef linux}
procedure TForm2.CopyLib;
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
  Panel1.Caption:=('开始拷贝lib文件到当前目录（'+LowerCase({$I %FPCTARGETCPU%})+'-'+LowerCase({$I %FPCTARGETOS%})+'）...');
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
    Panel1.Caption:=('没找到libc.so')
  else
  begin
    LibFileList:=TStringList.Create;
    y:=crt.WhereY;
    FileList := TStringList.Create;
    //ReadLn;
    //ClrScr;
    try
      // 获取所有文件
      FindAllFiles(FileList, SourceFile, '*.*', False);

      for i := 0 to FileList.Count - 1 do
      begin
        fn:=ExtractFileName(FileList[i]);
        if ISLinkFile(FileList[i],s) then
        begin//软连接文件
          if copy(s,1,1)=SetDirSeparators('/') then
          //if pos(SetDirSeparators('/'),s)>0 then
            n1:=s
          else
            n1:=ExtractFilePath(FileList[i])+s;
          n2:=TargetFile+ExtractFileName(FileList[i]);
          CopyFile(n1,n2,[cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
        end
        else
          CopyFile(FileList[i],TargetFile+ExtractFileName(s),
           [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
        LibFileList.Add(fn);
        //GotoXY(1, y);
        Panel1.Caption:=(IntToStr(i+1)+'/'+IntToStr(FileList.Count));
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
        //libc.so修改完成
        Panel1.Caption:=('lib文件拷贝完成');
      end;
    finally
       FileList.Free;
    end;
  end;
end;
{$endif}

{$R *.lfm}

procedure TForm2.btnListenClick(Sender: TObject);
var
  ini: TIniFile;
begin
  Timer1.Enabled := False;
  ini := TIniFile.Create('QFRemoteDebugServer.ini');
  ini.WriteString('系统参数', '端口', eServerPort.Text);
  ini.Free;
  with RtcHttpServer1 do
  begin
    if not isListening then
    begin
      eServerPort.Enabled := False;
      ServerPort := RtcString(eServerPort.Text);
      Listen;
    end
    else
    begin
      StopListen;
      eServerPort.Enabled := True;
    end;
  end;
end;

procedure TForm2.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  ini: TIniFile;
begin
  ini := TIniFile.Create('QFRemoteDebugServer.ini');
  ini.WriteString('系统参数', '端口', eServerPort.Text);
  ini.Free;
end;

procedure TForm2.FormCreate(Sender: TObject);
var
  ini: TIniFile;
begin
  Memo1.Lines.Clear;
  Panel1.Caption := GetLocalIP;
  Label2.Caption := Panel1.Caption;
  ini := TIniFile.Create('QFRemoteDebugServer.ini');
  eServerPort.Text := ini.ReadString('系统参数', '端口', '8080');
  ini.Free;
  Timer1.Enabled := True;
end;

procedure TForm2.Timer1Timer(Sender: TObject);
begin
  btnListenClick(Self);
end;

procedure TForm2.RtcHttpServer1Connect(Sender: TRtcConnection);
begin
  if Memo1.Lines.Count > 100 then
    Memo1.Lines.Clear;
  Memo1.Lines.Add(FormatDateTime('yyyy-mm-dd h:nn:ss', now));
end;

procedure TForm2.RtcHttpServer1ListenStart(Sender: TRtcConnection);
begin
  with TRtcDataServer(Sender) do
    if not inMainThread then
      Sync(@RtcHttpServer1ListenStart)
    else
      btnListen.Caption := 'Stop Listen';
end;

procedure TForm2.RtcHttpServer1ListenStop(Sender: TRtcConnection);
begin
  with TRtcDataServer(Sender) do
    if not inMainThread then
      Sync(@RtcHttpServer1ListenStop)
    else
      btnListen.Caption := 'Listen';
end;

procedure TForm2.RtcDataProvider1CheckRequest(Sender: TRtcConnection);
var
  fileName: string;
begin
  with TRtcDataServer(Sender) do
  begin
    // 处理文件上传请求
    if (Request.Method = 'PUT') and (UpperCase(Request.FileName) = '/DEBUG') and
      (Request.Query['file'] <> '') then
    begin
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
        Panel1.Caption:=ExtractFileName(fileName)+'下载中';
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

procedure TForm2.RtcDataProvider1DataReceived(Sender: TRtcConnection);
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
        Memo1.Lines.Add(Request.Query['file']+'上传成功。');
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
        Memo1.Lines.Add(Request.Query['file']+'上传成功。');
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
        //Process.Executable := 'gdbserver';
        //Process.Parameters.Add(':2345');
        //Process.Parameters.Add(f1);
        Process.Executable := 'sh';
        Process.Parameters.Add('run.sh');
        //Process.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
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

procedure TForm2.RtcDataProvider1DataSent(Sender: TRtcConnection);
var
  s: RtcString;
  requestType: string;
  fileName: string;
  fileSize: int64;
  bytesSent: int64;
  bytesToSend: int64;
  bufferSize: integer;
begin
  with TRtcDataServer(Sender) do
  begin
    requestType := Request.Info.AsString['request_type'];

    if requestType = 'download' then
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
        Panel1.Caption:= Label2.Caption;
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


end.
