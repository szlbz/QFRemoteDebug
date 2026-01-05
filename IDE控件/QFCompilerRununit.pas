unit QFCompilerRununit;

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

  { TTQFCompilerRun }

  { TQFCompilerRun }

  TQFCompilerRun = class(TForm)
    BtSaveConfig: TButton;
    CBOS: TComboBox;
    CBCPU: TComboBox;
    Label1: TLabel;
    Label2: TLabel;
    btnRemoteDebug: TButton;
    pInfo: TPanel;
    procedure BtSaveConfigClick(Sender: TObject);
    procedure eServerAddrExit(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure RtcDataRequest1DataIn(Sender: TRtcConnection);
    procedure btnRemoteDebugClick(Sender: TObject);
    procedure RtcDataRequest1BeginRequest(Sender: TRtcConnection);
    procedure RtcDataRequest1DataOut(Sender: TRtcConnection);
    procedure RtcDataRequest1DataSent(Sender: TRtcConnection);
    procedure SetProjectConfig;
    procedure fixLib(CrossPaths:String);
  private
    { Private declarations }
    LibFileList:TStringList;
    Nextno:Int64;
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
  QFCompilerRun: TQFCompilerRun;
  QFCompilerRunCreator: TIDEWindowCreator;

procedure ShowQFCompilerRun(Sender: TObject);
procedure Register;

implementation

{$R *.lfm}

//dock windows用
procedure CreateTQFCompilerRun(Sender: TObject; aFormName: string;
  var AForm: TCustomForm; DoDisableAutoSizing: boolean);
begin
  if CompareText(aFormName, 'QFCompilerRun')<>0 then
  begin
    DebugLn(['ERROR: CreateTQFCompilerRun: there is already a form with '
      +'this name']);
    exit;
  end;
  IDEWindowCreators.CreateForm(AForm, TQFCompilerRun,
    DoDisableAutoSizing,
    LazarusIDE.OwningComponent);
  AForm.Name:=aFormName;
  QFCompilerRun:=AForm as TQFCompilerRun;
end;

procedure ShowQFCompilerRun(Sender: TObject);
begin
  QFCompilerRun:=TQFCompilerRun.Create(nil);
  QFCompilerRun.ShowModal;
  QFCompilerRun.Free;
end;

procedure Register;
var
  CmdCatToolMenu: TIDECommandCategory;
  ToolQFCompilerRunCommand: TIDECommand;
  MenuItemCaption: String;
  MenuCommand: TIDEMenuCommand;
begin
  // register shortcut and menu item
  MenuItemCaption:='QFCompilerRun';//'远程调试助手'; // <- this caption should be replaced by a resourcestring
  // search shortcut category
  CmdCatToolMenu:=IDECommandList.FindCategoryByName(CommandCategoryCustomName);//CommandCategoryToolMenuName);
  // register shortcut
  ToolQFCompilerRunCommand:=RegisterIDECommand(CmdCatToolMenu,
    'QFCompilerRun',
    MenuItemCaption,
    IDEShortCut(VK_UNKNOWN, []), // <- set here your default shortcut
    CleanIDEShortCut, nil, @ShowQFCompilerRun);

  // register menu item in Project menu
  MenuCommand:=RegisterIDEMenuCommand(itmRunBuilding,//mnuRun, //新注册菜单的位置
    'QFCompilerRun', //菜单名--唯一标识（不能有中文）
    MenuItemCaption,//菜单标题
    nil, nil,ToolQFCompilerRunCommand);

end;

procedure TQFCompilerRun.BtSaveConfigClick(Sender: TObject);
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
    TargetOS:=CBOS.Items[CBOS.ItemIndex];;

    LazarusIDE.ActiveProject.LazCompilerOptions.TargetCPU:=TargetCPU;
    LazarusIDE.ActiveProject.LazCompilerOptions.TargetOS:=TargetOS;

    TargetCPUOS:=TargetCPU+'-'+TargetOS;

    eGDBFileName := StringReplace(LazarusIDE.GetPrimaryConfigPath,'config_lazarus','fpcbootstrap',[]);

    if SetDirSeparators(eGDBFileName[Length(eGDBFileName)])<>SetDirSeparators('/') then
      eGDBFileName:=eGDBFileName+SetDirSeparators('/');
    eGDBFileName:=SetDirSeparators(eGDBFileName+GetCompiledTargetCPU+'-'+GetCompiledTargetOS+
      '/gdb/'+TargetCPUOS+'/gdb'{$ifdef windows}+'.exe'{$endif});

    Config.DeletePath('ProjectOptions/Debugger');
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

procedure TQFCompilerRun.eServerAddrExit(Sender: TObject);
begin
  SetProjectConfig;
end;

procedure TQFCompilerRun.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if IsDownLibFile then
  begin
    IsDownLibFile:=False;
    CanClose:=False;
  end;
end;

procedure TQFCompilerRun.SetProjectConfig;
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
    Config.SetValue('CompilerOptions/CodeGeneration/TargetCPU/Value',TargetCPU);
    Config.SetValue('CompilerOptions/CodeGeneration/TargetOS/Value',TargetOS);
  end
  else
  begin
    ShowMessage('新建project，先保存project再使用。');
    btnRemoteDebug.Enabled:=False;
  end;
  LazarusIDE.DoSaveAll([sfProjectSaving]);  //保存
  Config.Free;
end;

procedure TQFCompilerRun.FormCreate(Sender: TObject);
begin
  SetProjectConfig;
  CBCPU.Text:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetCPU;
  CBOS.Text:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetOS;
  if CBOS.ItemIndex<0 then CBOS.ItemIndex:=0;
end;

procedure TQFCompilerRun.RtcDataRequest1DataIn(Sender: TRtcConnection);
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

procedure TQFCompilerRun.btnRemoteDebugClick(Sender: TObject);
begin
  BtSaveConfigClick(Self);
  LazarusIDE.DoOpenProjectFile(LazarusIDE.ActiveProject.ProjectInfoFile,[ofRevert]); //重新打开project
  btnRemoteDebug.Enabled:=False;
  //编译当前project
  if LazarusIDE.DoBuildProject(crBuild,[]) = mrOK then
  begin
    if (lowerCase(CBCPU.Text)=lowerCase({$I %FPCTARGETCPU%})) and
      (lowerCase(CBOS.Text)=lowerCase({$I %FPCTARGETOS%})) then
    begin
      LazarusIDE.DoRunProject;
      Close;
    end;
  end;
  btnRemoteDebug.Enabled:=True;
end;

procedure TQFCompilerRun.RtcDataRequest1BeginRequest(Sender: TRtcConnection);
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
    end
    else
    if Request.Info.AsString['request_type'] = 'downloadliblist' then
    begin
      // 下载请求
      DeleteFile(SetDirSeparators(LazarusIDE.GetPrimaryConfigPath+'\liblist.txt'));
      crosspath:=LazarusIDE.GetPrimaryConfigPath;
      crosspath:=crosspath.Replace('config_lazarus','',[]);
      crosspath:=SetDirSeparators(crosspath+'cross\lib\'+TargetCPUOS+'\');
      if DirectoryExists(crosspath) then
      begin
        DeleteDirectory(crosspath,False);
      end;
      ForceDirectories(crosspath);
      Request.Method := 'GET';
      Request.FileName := '/DOWNLOADLIBLIST';
      Request.Host := ServerAddr;
      Request.Query['file'] := 'liblist.txt';
      WriteHeader;
    end;
  end;
end;

procedure TQFCompilerRun.RtcDataRequest1DataOut(Sender: TRtcConnection);
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

procedure TQFCompilerRun.RtcDataRequest1DataSent(Sender: TRtcConnection);
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

procedure TQFCompilerRun.fixLib(CrossPaths:String);
const
  libs:array[1..7] of shortstring =(
  'libgdk-x11-2.0.so',
  'libgtk-x11-2.0.so',
  'libX11.so',
  'libgdk_pixbuf-2.0.so',
  'libpango-1.0.so',
  'libcairo.so',
  'libatk-1.0.so'
  );
var
  i:Integer;

  procedure cpf(p,f:String);
  var
    FileList : TStringList;
    SourceFile:String;
    TargetFile:String;
    i:Integer;
  begin
    try
      FileList := TStringList.Create;
      FindAllFiles(FileList, p, f+'*', False);

      for i := 0 to FileList.Count - 1 do
      begin
        CopyFile(FileList[i],p+f,
         [cffOverwriteFile, cffCreateDestDirectory,cffPreserveTime]);
        Break;
      end;
    finally
      FileList.Free;
    end;
  end;

begin
  for i:=1 to 7 do
  begin
    if not FileExists(CrossPaths+libs[i]) then
    begin
       cpf(CrossPaths,libs[i]);
    end;
  end;
end;

end.
