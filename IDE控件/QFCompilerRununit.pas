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
    CBSUBCPUOS: TComboBox;
    CheckBox1: TCheckBox;
    Label1: TLabel;
    Label2: TLabel;
    btnRemoteDebug: TButton;
    Label3: TLabel;
    pInfo: TPanel;
    procedure BtSaveConfigClick(Sender: TObject);
    procedure CBCPUChange(Sender: TObject);
    procedure eServerAddrExit(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure btnRemoteDebugClick(Sender: TObject);
    procedure SetProjectConfig;
    procedure SetProjectDebugConfig;
    procedure GetCrossLibList;
    procedure ModifyFpccfg;
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

function TQFCompilerRun.GetLibVer:String;
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

procedure TQFCompilerRun.ModifyFpccfg;
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
          f[i]:= '-FL/lib64/ld.so.1';//abi1.0;
      end;
      if CBSUBCPUOS.text='loongarch64-linux_abi2.0' then
      begin
        if LowerCase(Copy(f[i],1,12))=LowerCase('-FL/lib64/ld') then
          f[i]:= '-FL/lib64/ld-linux-loongarch-lp64d.so.1' ; //abi2.0
      end;
    end;
    f.SaveToFile(p);
  finally
    f.Free;
  end;
end;

procedure TQFCompilerRun.GetCrossLibList;
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
    //if  libdir='loongarch64-linux' then
      CBSUBCPUOS.ItemIndex:=CBSUBCPUOS.Items.IndexOf(GetlibVer);
    //else
      //CBSUBCPUOS.ItemIndex:=0;
  finally
     LibDirList.Free;
  end;
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

procedure TQFCompilerRun.CBCPUChange(Sender: TObject);
begin
  GetCrossLibList;
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

procedure TQFCompilerRun.SetProjectDebugConfig;
var
  Config: TConfigStorage;
  TargetFile:String;
  GenerateDebugInfo:String;
begin
  Config:=GetIDEConfigStorage(LazarusIDE.ActiveProject.ProjectInfoFile,true);
  if Config.GetValue('ProjectOptions/Version/Value','')<>'' then
  begin
    GenerateDebugInfo:=Config.GetValue('CompilerOptions/Linking/Debugging/GenerateDebugInfo/Value','');
    if (CheckBox1.Checked) then
    Config.SetValue('CompilerOptions/Linking/Debugging/GenerateDebugInfo/Value','False')
      //Config.DeleteValue('CompilerOptions/Linking/Debugging/GenerateDebugInfo')
    else
      Config.SetValue('CompilerOptions/Linking/Debugging/GenerateDebugInfo/Value','True');
  end
  else
  begin
    ShowMessage('新建project，先保存project再使用。');
    btnRemoteDebug.Enabled:=False;
  end;
  Config.Free;
end;

procedure TQFCompilerRun.FormCreate(Sender: TObject);
begin
  SetProjectConfig;
  CBCPU.Text:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetCPU;
  CBOS.Text:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetOS;
  if CBOS.ItemIndex<0 then CBOS.ItemIndex:=0;
  GetCrossLibList;
end;

procedure TQFCompilerRun.btnRemoteDebugClick(Sender: TObject);
begin
  BtSaveConfigClick(Self);
  ModifyFpccfg;
  SetProjectDebugConfig;
  LazarusIDE.DoOpenProjectFile(LazarusIDE.ActiveProject.ProjectInfoFile,[ofRevert]); //重新打开project
  btnRemoteDebug.Enabled:=False;
  //编译当前project
  if LazarusIDE.DoBuildProject(crBuild,[]) = mrOK then
  begin
    if ((lowerCase(CBCPU.Text)=lowerCase({$I %FPCTARGETCPU%})) and
      (lowerCase(CBOS.Text)=lowerCase({$I %FPCTARGETOS%}))) or
      (lowerCase(copy(CBOS.Text,1,3))='win') and (copy(lowerCase({$I %FPCTARGETOS%}),1,3)='win') then
    begin
      LazarusIDE.DoRunProject;
      Close;
    end;
  end;
  btnRemoteDebug.Enabled:=True;
end;

end.
