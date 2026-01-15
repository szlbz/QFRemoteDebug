unit QFRemoteDebugunit;

{$MODE Delphi}

interface

uses
  LCLIntf, LCLType, LMessages, Messages, SysUtils, Classes, Graphics, Controls, Forms,
  Dialogs, rtcDataCli, rtcInfo, rtcConn, rtcHttpCli, StdCtrls, ExtCtrls, IniFiles,
  rtcSystem, rtcCliModule,
  //IDE 调试助手需要用到的单元
  DefineTemplates, CompOptsIntf, TransferMacros,
  LCLProc, BaseIDEIntf, ProjectIntf, LazConfigStorage,
  ComCtrls,
  FileUtil,
  IdeDebuggerOpts,
  IDECommands, IDEWindowIntf, LazIDEIntf, MenuIntf
  , Types;

type

  { TQFRemoteDebug }

  TQFRemoteDebug = class(TForm)
    BtSaveConfig: TButton;
    CBOS: TComboBox;
    CBCPU: TComboBox;
    CBSUBCPUOS: TComboBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    eServerPort: TEdit;
    Label5: TLabel;
    eServerAddr: TEdit;
    btnRemoteDebug: TButton;
    Label8: TLabel;
    Label9: TLabel;
    RtcHttpClient1: TRtcHttpClient;
    RtcDataRequest1: TRtcDataRequest;
    pInfo: TPanel;
    procedure btnConnectClick(Sender: TObject);
    procedure BtSaveConfigClick(Sender: TObject);
    procedure CBOSChange(Sender: TObject);
    procedure eServerAddrExit(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure RtcDataRequest1DataIn(Sender: TRtcConnection);
    procedure btnRemoteDebugClick(Sender: TObject);
    procedure RtcDataRequest1BeginRequest(Sender: TRtcConnection);
    procedure RtcDataRequest1DataOut(Sender: TRtcConnection);
    procedure RtcDataRequest1DataSent(Sender: TRtcConnection);
    procedure RtcDataRequest1DataReceived(Sender: TRtcConnection);
    procedure SetProjectConfig;
    procedure GetCrossLibList;
    procedure ModifyFpccfg;
    function GetlibVer:String;
 private
    { Private declarations }
    TargetCPUOS:String;
    eRequestFileName:String;
    eLocalFileName:String;
    eGDBFileName:String;
    crosspath:String;
    IsDownLibFile:Boolean;
  public
    { Public declarations }
  end;

var
  QFRemoteDebug: TQFRemoteDebug;
  QFRemoteDebugCreator: TIDEWindowCreator;

procedure ShowQFRemoteDebug(Sender: TObject);
procedure Register;

implementation

{$R *.lfm}

//dock windows用
procedure CreateQFRemoteDebug(Sender: TObject; aFormName: string;
  var AForm: TCustomForm; DoDisableAutoSizing: boolean);
begin
  if CompareText(aFormName, 'QFRemoteDebug')<>0 then
  begin
    DebugLn(['ERROR: CreateQFRemoteDebug: there is already a form with '
      +'this name']);
    exit;
  end;
  IDEWindowCreators.CreateForm(AForm, TQFRemoteDebug,
    DoDisableAutoSizing,
    LazarusIDE.OwningComponent);
  AForm.Name:=aFormName;
  QFRemoteDebug:=AForm as TQFRemoteDebug;
end;

procedure ShowQFRemoteDebug(Sender: TObject);
begin
  QFRemoteDebug:=TQFRemoteDebug.Create(nil);
  QFRemoteDebug.ShowModal;
  QFRemoteDebug.Free;
end;

procedure Register;
var
  CmdCatToolMenu: TIDECommandCategory;
  ToolQFRemoteDebugCommand: TIDECommand;
  MenuItemCaption: String;
  MenuCommand: TIDEMenuCommand;
begin
  // register shortcut and menu item
  MenuItemCaption:='QFRemoteDebug Assistant';//'远程调试助手'; // <- this caption should be replaced by a resourcestring
  // search shortcut category
  CmdCatToolMenu:=IDECommandList.FindCategoryByName(CommandCategoryCustomName);//CommandCategoryToolMenuName);
  // register shortcut
  ToolQFRemoteDebugCommand:=RegisterIDECommand(CmdCatToolMenu,
    'QFRemoteDebug',
    MenuItemCaption,
    IDEShortCut(VK_F10, []), // <- set here your default shortcut
    CleanIDEShortCut, nil, @ShowQFRemoteDebug);

  // register menu item in Project menu
  MenuCommand:=RegisterIDEMenuCommand(itmRunBuilding,//mnuRun, //新注册菜单的位置
    'QFRemoteDebug', //菜单名--唯一标识（不能有中文）
    MenuItemCaption,//菜单标题
    nil, nil,ToolQFRemoteDebugCommand);

end;

function TQFRemoteDebug.GetlibVer:String;
var
  f:TStringList;
  p,s,str:String;
  i:Integer;
begin
  Result:='';
  p:=LazarusIDE.GetPrimaryConfigPath;
  p:=p.Replace('config_lazarus','',[]);
  p:=SetDirSeparators(p+'fpc\bin\'+lowerCase({$I %FPCTARGETCPU%})+'-'+lowerCase({$I %FPCTARGETOS%})+'\fpc.cfg');
  try
    f:=TStringList.Create;
    f.LoadFromFile(p);
    for i:=0 to f.Count-1 do
    begin
      str:=SetDirSeparators('\cross\lib\'+CBCPU.Text+'-'+CBOS.Text);
      if pos(str,SetDirSeparators(f[i]))>0 then
      begin
        Result:=Copy(f[i],pos(CBCPU.Text+'-'+CBOS.Text,f[i]),Length(f[i]));
        Break;
      end;
    end;
  finally
    f.Free;
  end;
end;

procedure TQFRemoteDebug.ModifyFpccfg;
var
  f:TStringList;
  p,s:String;
  i:Integer;
begin
  p:=LazarusIDE.GetPrimaryConfigPath;
  p:=p.Replace('config_lazarus','',[]);
  p:=SetDirSeparators(p+'fpc\bin\'+lowerCase({$I %FPCTARGETCPU%})+'-'+lowerCase({$I %FPCTARGETOS%})+'\fpc.cfg');
  try
    f:=TStringList.Create;
    f.LoadFromFile(p);
    for i:=0 to f.Count-1 do
    begin
      if pos(SetDirSeparators('\cross\lib\'+CBCPU.Text+'-'+CBOS.Text), f[i])>0 then
      begin
        s:=Copy(f[i],1,pos(CBCPU.Text+'-'+CBOS.Text,f[i])-1);
        f[i]:=s+CBSUBCPUOS.Text;
      end;
      if CBSUBCPUOS.Text='loongarch64-linux' then
      begin
        if LowerCase(Copy(f[i],1,12))=LowerCase('-FL/lib64/ld') then
          f[i]:= '-FL/lib64/ld.so.1';
      end;
      if CBSUBCPUOS.text='loongarch64-linux_abi2.0' then
      begin
        if LowerCase(Copy(f[i],1,12))=LowerCase('-FL/lib64/ld') then
          f[i]:= '-FL/lib64/ld-linux-loongarch-lp64d.so.1' ;
      end;
    end;
    f.SaveToFile(p);
  finally
    f.Free;
  end;
end;

procedure TQFRemoteDebug.GetCrossLibList;
var
  LibDirList:TStringList;
  i:Integer;
  libdir,s:String;
begin
  crosspath:=LazarusIDE.GetPrimaryConfigPath;
  crosspath:=crosspath.Replace('config_lazarus','',[]);
  crosspath:=SetDirSeparators(crosspath+'cross\lib\');
  try
    CBSUBCPUOS.Items.Clear;
    LibDirList:=TStringList.Create;
    LibDirList:=FindAllDirectories(crosspath, False);
    libdir:=CBCPU.Text+'-'+CBOS.Text;
    for i := 0 to LibDirList.Count - 1 do
    begin
      if pos(libdir, LibDirList[i])>0 then
      begin
        s:=Copy(LibDirList[i],pos(libdir,LibDirList[i]),Length(LibDirList[i]));
        CBSUBCPUOS.Items.Add(s);
      end;
    end;
    CBSUBCPUOS.ItemIndex:=CBSUBCPUOS.Items.IndexOf(GetlibVer);
  finally
    LibDirList.Free;
  end;
end;

procedure TQFRemoteDebug.btnConnectClick(Sender: TObject);
begin
  with RtcHttpClient1 do
  begin
    if not isConnected then
    begin
      ServerAddr := eServerAddr.Text;
      ServerPort := eServerPort.Text;
      Connect;
    end
    else
      Disconnect;
  end;
end;

procedure TQFRemoteDebug.BtSaveConfigClick(Sender: TObject);
var
  Config: TConfigStorage;
  TargetFile:String;
  TargetCPU:String;
  TargetOS:String;
  guid: TGUID;
begin
  Config:=GetIDEConfigStorage(LazarusIDE.ActiveProject.ProjectInfoFile,true);
  if Config.GetValue('ProjectOptions/Version/Value','')<>'' then
  begin
    TargetCPU:=CBCPU.Items[CBCPU.ItemIndex];
    TargetOS:=CBOS.Items[CBOS.ItemIndex];

    LazarusIDE.ActiveProject.LazCompilerOptions.TargetCPU:=TargetCPU;
    LazarusIDE.ActiveProject.LazCompilerOptions.TargetOS:=TargetOS;

    TargetCPUOS:=TargetCPU+'-'+TargetOS;

    eGDBFileName := StringReplace(LazarusIDE.GetPrimaryConfigPath,'config_lazarus','fpcbootstrap',[]);

    if SetDirSeparators(eGDBFileName[Length(eGDBFileName)])<>SetDirSeparators('/') then
      eGDBFileName:=eGDBFileName+SetDirSeparators('/');
    eGDBFileName:=SetDirSeparators(eGDBFileName+GetCompiledTargetCPU+'-'+GetCompiledTargetOS+
      '/gdb/'+TargetCPUOS+'/gdb'{$ifdef windows}+'.exe'{$endif});

    CreateGUID(guid);
    Config.DeletePath('ProjectOptions/Debugger');
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Version','1');
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/ConfigName','RemoteDebug');
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/ConfigClass','TGDBMIServerDebugger');
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/DebuggerFilename',eGDBFileName);
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/Active','True');
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/UID',GUIDToString(guid));
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/Properties/Debugger_Remote_Hostname',eServerAddr.text);
    Config.SetValue('CompilerOptions/CodeGeneration/TargetCPU/Value',TargetCPU);
    Config.SetValue('CompilerOptions/CodeGeneration/TargetOS/Value',TargetOS);
    LazarusIDE.DoSaveAll([sfProjectSaving]);  //保存
    Config.Free;
  end
  else
  begin
    ShowMessage('新建project，先保存project再使用。');
    btnRemoteDebug.Enabled:=False;
  end;
end;

procedure TQFRemoteDebug.CBOSChange(Sender: TObject);
begin
  GetCrossLibList;
end;

procedure TQFRemoteDebug.eServerAddrExit(Sender: TObject);
begin
  SetProjectConfig;
end;

procedure TQFRemoteDebug.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  ini:TIniFile;
begin
  ini:=TIniFile.Create(SetDirSeparators(LazarusIDE.GetPrimaryConfigPath+'\RemoteDebugConfig.ini'));
  ini.WriteString('参数','ip',eServerAddr.Text);
  ini.WriteString('参数','port',eServerPort.Text);
  ini.Free;
end;

procedure TQFRemoteDebug.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if IsDownLibFile then
  begin
    IsDownLibFile:=False;
    CanClose:=False;
  end;
end;

procedure TQFRemoteDebug.SetProjectConfig;
var
  Config: TConfigStorage;
  TargetFile:String;
  TargetCPU:String;
  TargetOS:String;
  guid: TGUID;
  guidStr: string;
begin
  LazarusIDE.DoSaveAll([sfProjectSaving]);  //保存

  Config:=GetIDEConfigStorage(LazarusIDE.ActiveProject.ProjectInfoFile,true);
  if Config.GetValue('ProjectOptions/Version/Value','')<>'' then
  begin
    TargetCPU:=Config.GetValue('CompilerOptions/CodeGeneration/TargetCPU/Value','');
    TargetOS:=Config.GetValue('CompilerOptions/CodeGeneration/TargetOS/Value','');
    if TargetCPU='' then
      TargetCPU:=lowerCase({$I %FPCTARGETCPU%});
    if TargetOS='' then
      TargetOS:=lowerCase({$I %FPCTARGETOS%});
    TargetCPUOS:=TargetCPU+'-'+TargetOS;
    if trim(TargetCPUOS)='-' then
      TargetCPUOS:=lowerCase({$I %FPCTARGETCPU%})+'-'+lowerCase({$I %FPCTARGETOS%});

    LazarusIDE.ActiveProject.LazCompilerOptions.TargetCPU:=TargetCPU;
    LazarusIDE.ActiveProject.LazCompilerOptions.TargetOS:=TargetOS;

    TargetFile:=Config.GetValue('CompilerOptions/Target/Filename/Value','');
    TargetFile:=TargetFile.Replace('$(TargetCPU)',TargetCPU,[]);
    TargetFile:=TargetFile.Replace('$(TargetOS)',TargetOS,[]);

    eGDBFileName:=StringReplace(LazarusIDE.GetPrimaryConfigPath,'config_lazarus','fpcbootstrap',[]);
    if SetDirSeparators(eGDBFileName[Length(eGDBFileName)])<>SetDirSeparators('/') then
      eGDBFileName:=eGDBFileName+SetDirSeparators('/');
    eGDBFileName:=SetDirSeparators(eGDBFileName+GetCompiledTargetCPU+'-'+GetCompiledTargetOS+
      '/gdb/'+TargetCPUOS+'/gdb'{$ifdef windows}+'.exe'{$endif});

    eLocalFileName:=ExtractFilePath(LazarusIDE.ActiveProject.ProjectInfoFile)+TargetFile;
    eRequestFileName:=TargetFile;
    Config.DeletePath('ProjectOptions/Debugger');
    CreateGUID(guid);
    // 转换为字符串
    guidStr := GUIDToString(guid);
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Version','1');
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/ConfigName','RemoteDebug');
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/ConfigClass','TGDBMIServerDebugger');
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/DebuggerFilename',eGDBFileName);
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/Active','True');
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/UID',guidStr);
    Config.SetValue('ProjectOptions/Debugger/ClassConfig/Config/Properties/Debugger_Remote_Hostname',eServerAddr.text);
    Config.SetValue('CompilerOptions/CodeGeneration/TargetCPU/Value',TargetCPU);
    Config.SetValue('CompilerOptions/CodeGeneration/TargetOS/Value',TargetOS);
    Config.SetValue('CompilerOptions/Linking/Debugging/GenerateDebugInfo/Value','True'); //强制启用Debug
  end
  else
  begin
    ShowMessage('新建project，先保存project再使用。');
    btnRemoteDebug.Enabled:=False;
  end;
  LazarusIDE.DoSaveAll([sfProjectSaving]);  //保存
  Config.Free;
end;

procedure TQFRemoteDebug.FormCreate(Sender: TObject);
var
  ini:TIniFile;
begin
  ini:=TIniFile.Create(SetDirSeparators(LazarusIDE.GetPrimaryConfigPath+'\RemoteDebugConfig.ini'));
  eServerAddr.Text:=ini.ReadString('参数','ip','');
  eServerPort.Text:=ini.ReadString('参数','port','8080');
  ini.Free;
  SetProjectConfig;
  CBCPU.Text:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetCPU;
  CBOS.Text:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetOS;
  if CBOS.ItemIndex<0 then CBOS.ItemIndex:=0;
  Label8.Caption:='Current Project Targget CPU / OS:';
  Label9.Caption:= TargetCPUOS;
  GetCrossLibList;
end;

procedure TQFRemoteDebug.RtcDataRequest1DataIn(Sender: TRtcConnection);
var
  requestType: string;
  ContentIn:Int64;
begin
  with Sender as TRtcDataClient do
  begin
    requestType := Request.Info.AsString['request_type'];

    if requestType = 'download' then
    begin
      ContentIn:=Response.ContentIn;
      if Response.ContentLength > 0 then
      begin
        pInfo.Caption := '下载:' + IntToStr(ContentIn) + '/' +
          IntToStr(Response.ContentLength) + ' [' +
          IntToStr(round(ContentIn / Response.ContentLength * 100)) + '%]';
      end
      else
      begin
        pInfo.Caption := '下载:' + IntToStr(ContentIn) +
          ' bytes received';
      end;
    end;
  end;
end;

procedure TQFRemoteDebug.btnRemoteDebugClick(Sender: TObject);
begin
  BtSaveConfigClick(Self);
  ModifyFpccfg;
  if pos('win',TargetCPUOS)<=0 then
  begin
    LazarusIDE.DoOpenProjectFile(LazarusIDE.ActiveProject.ProjectInfoFile,[ofRevert]); //重新打开project
    btnRemoteDebug.Enabled:=False;
    //编译当前project,编译成功后上传
    if LazarusIDE.DoBuildProject(crBuild,[]) = mrOK then
    begin
      if not RtcHttpClient1.isConnecting then
        btnConnectClick(Self);

      pInfo.Caption := '上传中...';
      with RtcDataRequest1 do
      begin
        // 先停止gdbserver
        Request.Info.AsString['request_type'] := 'deletefile';
        Post;
      end;
      with RtcDataRequest1 do
      begin
        // File Name on Server (need to URL_encode all Query parameters)
        Request.Info.AsString['request_type'] := 'debug';
        Request.Query['file'] := URL_Encode(Utf8Encode(eRequestFileName));
        // Local File Name
        Request.Info.asText['file'] := eLocalFileName;
        Post;
      end;
      LazarusIDE.DoRunProject;//运行要debug的project
    end
    else
      close;
    btnRemoteDebug.Enabled:=True;
  end
  else
    ShowMessage('windows程序暂时不支持远程调试！');
end;

procedure TQFRemoteDebug.RtcDataRequest1BeginRequest(Sender: TRtcConnection);
var
  s:Int64;
  f:String;
begin
  with TRtcDataClient(Sender) do
  begin
    if Request.Info.AsString['request_type'] = 'debug' then
    begin
      // 上传请求
      pInfo.Caption := 'Sending ...';
      Request.Method := 'PUT';
      Request.FileName := '/DEBUG';
      Request.Host := ServerAddr;
      f:=Request.Info.asText['file'];
      s:=File_Size(Request.Info.asText['file']);
      Request.ContentLength := s;
      WriteHeader;
    end
    else if Request.Info.AsString['request_type'] = 'download' then
    begin
      // 下载请求
      pInfo.Caption := 'Downloading ...';
      Request.Method := 'GET';
      Request.FileName := '/DOWNLOAD';
      Request.Host := ServerAddr;
       WriteHeader;
    end;
  end;
end;

procedure TQFRemoteDebug.RtcDataRequest1DataOut(Sender: TRtcConnection);
var
  requestType: string;
begin
  with Sender as TRtcDataClient do
  begin
    requestType := Request.Info.AsString['request_type'];

    if requestType = 'debug' then
    begin
      pInfo.Caption := '上传:' + IntToStr(Request.ContentOut) + '/' +
        IntToStr(Request.ContentLength) + ' [' +
        IntToStr(round(Request.ContentOut / Request.ContentLength * 100)) + '%]';
    end;
  end;
end;

procedure TQFRemoteDebug.RtcDataRequest1DataSent(Sender: TRtcConnection);
var
  bSize: int64;
begin
  with TRtcDataClient(Sender) do
  begin
    if Request.Info.AsString['request_type'] = 'debug' then
    begin
      if Request.ContentLength > Request.ContentOut then
      begin
        bSize := Request.ContentLength - Request.ContentOut;
        if bSize > 64000 then bSize := 64000;
        Write(Read_File(Request.Info.asText['file'], Request.ContentOut, bSize));
      end;
    end;
  end;
end;

procedure TQFRemoteDebug.RtcDataRequest1DataReceived(Sender: TRtcConnection);
var
  s: RtcString;
  requestType: string;
  FDownloadFileName:String;
begin
  with TRtcDataClient(Sender) do
  begin
    requestType := Request.Info.AsString['request_type'];

    if requestType = 'download' then
    begin
      // 读取数据并保存到文件
      s := Read;
      FDownloadFileName:='download\'+Request.Info.asText['file'];
      Write_File(FDownloadFileName, s, Request.ContentIn -length(s));

      if Response.Done then
      begin
        // 下载完成
        pInfo.Caption := 'Download Complete';
      end;
    end
    else if requestType = 'debug' then
    begin
      if Response.Done then
      begin
        pInfo.Caption := 'Done, Status = ' +
          IntToStr(Response.StatusCode) + ' ' + Response.StatusText;
        Close;
      end;
    end;
  end;
end;

end.
