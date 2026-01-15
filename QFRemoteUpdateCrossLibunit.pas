unit QFRemoteUpdateCrossLibunit;

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

  { TQFRemoteUpdateCrossLib }

  TQFRemoteUpdateCrossLib = class(TForm)
    btnUpdateLibrary: TButton;
    BtSaveConfig: TButton;
    Button1: TButton;
    CBOS: TComboBox;
    CBCPU: TComboBox;
    CBSUBCPUOS: TComboBox;
    Edit1: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    eServerPort: TEdit;
    Label5: TLabel;
    eServerAddr: TEdit;
    Label6: TLabel;
    Label7: TLabel;
    Label8: TLabel;
    RtcHttpClient1: TRtcHttpClient;
    RtcDataRequest1: TRtcDataRequest;
    pInfo: TPanel;
    procedure btnConnectClick(Sender: TObject);
    procedure btnUpdateLibraryClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure CBOSChange(Sender: TObject);
    procedure CBSUBCPUOSChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure RtcDataRequest1DataIn(Sender: TRtcConnection);
    procedure RtcDataRequest1BeginRequest(Sender: TRtcConnection);
    procedure RtcDataRequest1DataOut(Sender: TRtcConnection);
    procedure RtcDataRequest1DataSent(Sender: TRtcConnection);
    procedure RtcDataRequest1DataReceived(Sender: TRtcConnection);
    procedure DownLibFiles(i:int64);
    procedure fixLib(CrossPaths:String);
    procedure GetCrossLibList;
    function GetlibVer:String;
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
  QFRemoteUpdateCrossLib: TQFRemoteUpdateCrossLib;
  QFRemoteUpdateCrossLibCreator: TIDEWindowCreator;

procedure ShowQFRemoteUpdateCrossLib(Sender: TObject);
procedure Register;

implementation

{$R *.lfm}

//dock windows用
procedure CreateQFRemoteUpdateCrossLib(Sender: TObject; aFormName: string;
  var AForm: TCustomForm; DoDisableAutoSizing: boolean);
begin
  if CompareText(aFormName, 'QFRemoteUpdateCrossLib')<>0 then
  begin
    DebugLn(['ERROR: CreateQFRemoteUpdateCrossLib: there is already a form with '
      +'this name']);
    exit;
  end;
  IDEWindowCreators.CreateForm(AForm, TQFRemoteUpdateCrossLib,
    DoDisableAutoSizing,
    LazarusIDE.OwningComponent);
  AForm.Name:=aFormName;
  QFRemoteUpdateCrossLib:=AForm as TQFRemoteUpdateCrossLib;
end;

procedure ShowQFRemoteUpdateCrossLib(Sender: TObject);
begin
  QFRemoteUpdateCrossLib:=TQFRemoteUpdateCrossLib.Create(nil);
  QFRemoteUpdateCrossLib.ShowModal;
  QFRemoteUpdateCrossLib.Free;
end;

procedure Register;
var
  CmdCatToolMenu: TIDECommandCategory;
  ToolQFRemoteUpdateCrossLibCommand: TIDECommand;
  MenuItemCaption: String;
  MenuCommand: TIDEMenuCommand;
begin
  // register shortcut and menu item
  MenuItemCaption:='Update Cross Lib Assistant';// <- this caption should be replaced by a resourcestring
  // search shortcut category
  CmdCatToolMenu:=IDECommandList.FindCategoryByName(CommandCategoryCustomName);//CommandCategoryToolMenuName);
  // register shortcut
  ToolQFRemoteUpdateCrossLibCommand:=RegisterIDECommand(CmdCatToolMenu,
    'QFRemoteUpdateCrossLib',
    MenuItemCaption,
    IDEShortCut(VK_F5, []), // <- set here your default shortcut
    CleanIDEShortCut, nil, @ShowQFRemoteUpdateCrossLib);

  // register menu item in Project menu
  MenuCommand:=RegisterIDEMenuCommand(itmRunBuilding,//mnuRun, //新注册菜单的位置
    'QFRemoteUpdateCrossLib', //菜单名--唯一标识（不能有中文）
    MenuItemCaption,//菜单标题
    nil, nil,ToolQFRemoteUpdateCrossLibCommand);

end;

function TQFRemoteUpdateCrossLib.GetlibVer:String;
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

procedure TQFRemoteUpdateCrossLib.GetCrossLibList;
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
    btnUpdateLibrary.Caption:='update Cross Library : '+CBSUBCPUOS.Text;
  finally
    LibDirList.Free;
  end;
end;

procedure TQFRemoteUpdateCrossLib.btnConnectClick(Sender: TObject);
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

procedure TQFRemoteUpdateCrossLib.btnUpdateLibraryClick(Sender: TObject);
begin
  if MessageDlg('更新交叉编译lib','确定要更新交叉编译'+CBSUBCPUOS.Text+'lib文件？',mtConfirmation,mbYesNo,'')=mrYes then
  begin
    TargetCPUOS:=CBSUBCPUOS.Text;
    if pos('win',TargetCPUOS)<=0 then
    begin
      if btnUpdateLibrary.Caption= 'Downloading ...' then
      begin
        btnUpdateLibrary.Caption:='update Cross Library : '+TargetCPUOS;
        IsDownLibFile:=False;
      end
      else
        IsDownLibFile:=True;
      btnUpdateLibrary.Enabled:=False;
      if not RtcHttpClient1.isConnecting then
        btnConnectClick(Self);
      DeleteFile(SetDirSeparators(LazarusIDE.GetPrimaryConfigPath+ '\liblist.txt'));
      with RtcDataRequest1 do
      begin
        Request.Info.AsString['request_type'] :='downloadliblist';
        Request.Method := 'GET';
        Request.FileName := '/DOWNLOADLIBLIST';
        Post;
      end;
      btnUpdateLibrary.Enabled:=True;
    end
    else
      ShowMessage('windows程序不需要更新lib文件！');
  end;
end;

procedure TQFRemoteUpdateCrossLib.Button1Click(Sender: TObject);
var
  pathcross:String;
begin
  pathcross:=LazarusIDE.GetPrimaryConfigPath;
  pathcross:=pathcross.Replace('config_lazarus','',[]);
  pathcross:=SetDirSeparators(pathcross+'cross\lib\'+CBCPU.Text+'-'+CBOS.Text+'-'+Edit1.Text+'\');
  if (trim(Edit1.Text)<>'') and (not DirectoryExists(pathcross)) then
  begin
    ForceDirectories(pathcross);
    GetCrossLibList;
    CBSUBCPUOS.ItemIndex:=CBSUBCPUOS.Items.IndexOf(CBCPU.Text+'-'+CBOS.Text+'-'+Edit1.Text);
    Edit1.Text:='';
  end;
end;

procedure TQFRemoteUpdateCrossLib.CBOSChange(Sender: TObject);
begin
  GetCrossLibList;
end;

procedure TQFRemoteUpdateCrossLib.CBSUBCPUOSChange(Sender: TObject);
begin
  btnUpdateLibrary.Caption:='update Cross Library : '+CBSUBCPUOS.Text;
end;

procedure TQFRemoteUpdateCrossLib.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  ini:TIniFile;
begin
  ini:=TIniFile.Create(SetDirSeparators(LazarusIDE.GetPrimaryConfigPath+'\RemoteDebugConfig.ini'));
  ini.WriteString('参数','ip',eServerAddr.Text);
  ini.WriteString('参数','port',eServerPort.Text);
  ini.Free;
end;

procedure TQFRemoteUpdateCrossLib.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if IsDownLibFile then
  begin
    IsDownLibFile:=False;
    CanClose:=False;
  end;
end;

procedure TQFRemoteUpdateCrossLib.FormCreate(Sender: TObject);
var
  ini:TIniFile;
  Config: TConfigStorage;
  TargetCPU,TargetOS:String;
begin
  try
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
    end;
  finally
    Config.free;
  end;
  ini:=TIniFile.Create(SetDirSeparators(LazarusIDE.GetPrimaryConfigPath+'\RemoteDebugConfig.ini'));
  eServerAddr.Text:=ini.ReadString('参数','ip','');
  eServerPort.Text:=ini.ReadString('参数','port','8080');
  ini.Free;
  CBCPU.Text:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetCPU;
  CBOS.Text:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetOS;
  if CBOS.ItemIndex<0 then CBOS.ItemIndex:=0;
  btnUpdateLibrary.Caption:='update Cross Library : '+TargetCPUOS;
  Label6.Caption:= '';
  Label7.Caption:='';
  GetCrossLibList;
end;

procedure TQFRemoteUpdateCrossLib.RtcDataRequest1DataIn(Sender: TRtcConnection);
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
        pInfo.Caption :=Format('%s: %d%% (%.1f/%.1f MB)',
        ['下载',
        round((ContentIn / Response.ContentLength) * 100),
        ContentIn/1024/1024,
        Response.ContentLength /1024 /1024]);
      end
      else
      begin
        pInfo.Caption := '下载:' + IntToStr(ContentIn) +
          ' bytes received';
      end;
    end;
  end;
end;

procedure TQFRemoteUpdateCrossLib.RtcDataRequest1BeginRequest(Sender: TRtcConnection);
var
  s:Int64;
  f:String;
begin
  with TRtcDataClient(Sender) do
  begin
    if Request.Info.AsString['request_type'] = 'download' then
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
      btnUpdateLibrary.Caption := 'Downloading ...';
      Request.Method := 'GET';
      Request.FileName := '/DOWNLOADLIBLIST';
      Request.Host := ServerAddr;
      Request.Query['file'] := 'liblist.txt';
      WriteHeader;
    end;
  end;
end;

procedure TQFRemoteUpdateCrossLib.RtcDataRequest1DataOut(Sender: TRtcConnection);
//var
//  requestType: string;
begin
  //with Sender as TRtcDataClient do
  //begin
  //  requestType := Request.Info.AsString['request_type'];
  //end;
end;

procedure TQFRemoteUpdateCrossLib.RtcDataRequest1DataSent(Sender: TRtcConnection);
//var
//  bSize: int64;
begin
  //with TRtcDataClient(Sender) do
  //begin
  //  if Request.Info.AsString['request_type'] = 'debug' then
  //  begin
  //    if Request.ContentLength > Request.ContentOut then
  //    begin
  //      bSize := Request.ContentLength - Request.ContentOut;
  //      if bSize > 64000 then bSize := 64000;
  //      Write(Read_File(Request.Info.asText['file'], Request.ContentOut, bSize));
  //    end;
  //  end;
  //end;
end;

procedure TQFRemoteUpdateCrossLib.DownLibFiles(i:int64);
var
  files,path:String;
begin
  files:='///'+CBCPU.Text+'-'+CBOS.Text+'/'+LibFileList.ValueFromIndex[i];
  Label6.Caption:=IntToStr(i+1)+' / '+inttostr(LibFileList.Count) ;
  Label7.Caption:=LibFileList.ValueFromIndex[i];
  path:=LazarusIDE.GetPrimaryConfigPath;
  path:=path.Replace('config_lazarus','',[]);
  path:=SetDirSeparators(path+'cross\lib\'+TargetCPUOS+'\');
  if not DirectoryExists(path) then
      ForceDirectories(path);
  DeleteFile(path+LibFileList.ValueFromIndex[i]);
  with RtcDataRequest1 do
  begin
    Request.Info.AsString['request_type'] :='download';
    Request.Method := 'GET';
    Request.FileName := '/DOWNLOAD';
    Request.Query['file'] :=URL_Encode(Utf8Encode(files));
    Request.Info.asText['file'] := LibFileList.ValueFromIndex[i];
    Post;
  end;
end;

procedure TQFRemoteUpdateCrossLib.fixLib(CrossPaths:String);
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

procedure TQFRemoteUpdateCrossLib.RtcDataRequest1DataReceived(Sender: TRtcConnection);
var
  s: RtcString;
  requestType: string;
  FDownloadFileName:String;
begin
  with TRtcDataClient(Sender) do
  begin
    requestType := Request.Info.AsString['request_type'];

    if requestType = 'downloadliblist' then
    begin
      // 读取数据并保存到文件
      s := Read;
      FDownloadFileName:=SetDirSeparators(LazarusIDE.GetPrimaryConfigPath+'\liblist.txt');
      Write_File(FDownloadFileName, s, Request.ContentIn -length(s));

      if Response.Done then
      begin
        // 下载完成
        LibFileList:=TStringList.Create;
        LibFileList.LoadFromFile(SetDirSeparators(LazarusIDE.GetPrimaryConfigPath+'\liblist.txt'));
        Nextno:=0;
        DownLibFiles(Nextno);
      end;
    end
    else
    if requestType = 'download' then
    begin
      // 读取数据并保存到文件
      s := Read;
      if LibFileList<>nil then
      begin
        FDownloadFileName:=LazarusIDE.GetPrimaryConfigPath;
        FDownloadFileName:=FDownloadFileName.Replace('config_lazarus','',[]);
        FDownloadFileName:=FDownloadFileName+'cross\lib\'+TargetCPUOS+'\'+
        Request.Info.asText['file'];
      end
      else
      begin
        FDownloadFileName:='download\'+Request.Info.asText['file'];
      end;
      Write_File(FDownloadFileName, s, Request.ContentIn -length(s));

      if Response.Done then
      begin
        // 下载完成
        pInfo.Caption := 'Download Complete';
        if LibFileList<>nil then
        begin
          if (Nextno<LibFileList.Count-1) and (IsDownLibFile) then
          begin
            Nextno:=Nextno+1;
            DownLibFiles(Nextno);
          end
          else
          begin
            IsDownLibFile:=False;
            btnUpdateLibrary.Caption:='update Cross Library : '+TargetCPUOS;
            pInfo.Caption:='update Cross Library Done！';
            Label7.Caption:='';
            LibFileList.Free;
            FDownloadFileName:=LazarusIDE.GetPrimaryConfigPath;
            FDownloadFileName:=FDownloadFileName.Replace('config_lazarus','',[]);
            FDownloadFileName:=FDownloadFileName+'cross\lib\'+TargetCPUOS+'\';
            //修正更新后可能出现缺少libgdk-x11-2.0.so等7个关键文件的问题
            //这7个so文件是编译GTK2应用不可缺少的文件
            fixLib(FDownloadFileName);
          End;
        end;
      end;
    end;
  end;
end;

end.
