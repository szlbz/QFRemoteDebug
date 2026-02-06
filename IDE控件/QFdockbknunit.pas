unit QFdockbknunit;

{$mode objfpc}{$H+}

interface

uses
  LCLType,Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Buttons, ComCtrls, DOM, XMLRead, XMLWrite, FileUtil, LazFileUtils,IniFiles ,
  //IDE 调试助手需要用到的单元
  //AnchorDesktopOptions,
  AnchorDocking, AnchorDockStorage, AnchorDockOptionsDlg,XMLPropStorage ,
  Laz2_XMLCfg,
  CompOptsIntf,
  LCLProc, BaseIDEIntf, ProjectIntf, LazConfigStorage,
  IDECommands, IDEWindowIntf, LazIDEIntf, MenuIntf,  Types  ;

type

  { TDockbkFrm }

  TDockbkFrm = class(TForm)
    btnRestore: TBitBtn;
    btnBackup: TBitBtn;
    btnBrowseBackup: TButton;
    Button1: TButton;
    edtBackupFile: TEdit;
    GroupBox2: TGroupBox;
    Label2: TLabel;
    lblStatus: TLabel;
    ListBox1: TListBox;
    Memo1: TMemo;
    PageControl1: TPageControl;
    Panel2: TPanel;
    Panel3: TPanel;
    Panel4: TPanel;
    SaveDialog1: TSaveDialog;
    Splitter1: TSplitter;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    procedure btnBackupClick(Sender: TObject);
    procedure btnBrowseBackupClick(Sender: TObject);
    procedure btnRestoreClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ListBox1Click(Sender: TObject);
  private
    FBackupDir: string;
    FConfigFile: string;
    procedure LoadBackupList;
    procedure UpdateStatus(const Msg: string; IsError: Boolean = False);
  public

  end;

var
  DockbkFrm: TDockbkFrm;

procedure ShowDockbkFrm(Sender: TObject);
procedure Register;

implementation

{$R *.lfm}

procedure ShowDockbkFrm(Sender: TObject);
begin
  DockbkFrm:=TDockbkFrm.Create(nil);
  DockbkFrm.ShowModal;
  DockbkFrm.Free;
end;

procedure Register;
var
  CmdCatToolMenu: TIDECommandCategory;
  ToolQFCompilerRunCommand: TIDECommand;
  MenuItemCaption: String;
  MenuCommand: TIDEMenuCommand;
begin
  // register shortcut and menu item
  MenuItemCaption:='界面备份恢复工具';// <- this caption should be replaced by a resourcestring
  // search shortcut category
  CmdCatToolMenu:=IDECommandList.FindCategoryByName(CommandCategoryCustomName);//CommandCategoryToolMenuName);
  // register shortcut
  ToolQFCompilerRunCommand:=RegisterIDECommand(CmdCatToolMenu,
    'QFDockbk',
    MenuItemCaption,
    IDEShortCut(VK_UNKNOWN, []), // <- set here your default shortcut
    CleanIDEShortCut, nil, @ShowDockbkFrm);

  // register menu item in Project menu
  MenuCommand:=RegisterIDEMenuCommand(mnuTools,//mnuRun, //新注册菜单的位置
    'QFDockbk', //菜单名--唯一标识（不能有中文）
    MenuItemCaption,//菜单标题
    nil, nil,ToolQFCompilerRunCommand);

end;

{ TDockbkFrm }

procedure TDockbkFrm.FormCreate(Sender: TObject);
var
  ini:TiniFile;
begin
  // 设置默认路径
  FBackupDir := LazarusIDE.GetPrimaryConfigPath + PathDelim + 'backups' + PathDelim;
  ForceDirectories(FBackupDir);

  // 设置默认备份文件名
  edtBackupFile.Text := FBackupDir + 'dockbackup_' +
    FormatDateTime('yyyy-mm-dd_hhnnss', Now) + '.xml';

  // 加载备份列表
  LoadBackupList;

  UpdateStatus('就绪');

end;

procedure TDockbkFrm.btnBrowseBackupClick(Sender: TObject);
begin
  SaveDialog1.Filter := 'XML备份文件|*.xml|所有文件|*.*';
  SaveDialog1.InitialDir := FBackupDir;
  SaveDialog1.FileName := ExtractFileName(edtBackupFile.Text);
  if SaveDialog1.Execute then
    edtBackupFile.Text := SaveDialog1.FileName;
end;

procedure TDockbkFrm.btnBackupClick(Sender: TObject);
var
  ConfigFile, BackupFile: string;
  XMLConfig: TXMLConfigStorage;
begin
  BackupFile := edtBackupFile.Text;

  if Trim(BackupFile) = '' then
  begin
    UpdateStatus('请指定备份文件名', True);
    Exit;
  end;

  try
    XMLConfig:=TXMLConfigStorage.Create(BackupFile,false);
    try
      DockMaster.SaveLayoutToConfig(XMLConfig);
      DockMaster.SaveSettingsToConfig(XMLConfig);
      XMLConfig.WriteToDisk;
    finally
      XMLConfig.Free;
      UpdateStatus('备份成功: ' + ExtractFileName(BackupFile));
      LoadBackupList;
    end;
  except
    on E: Exception do begin
      UpdateStatus('备份失败', True);
    end;
  end;
end;

procedure TDockbkFrm.btnRestoreClick(Sender: TObject);
var
  BackupFile: string;
  XMLConfig:TXMLConfigStorage;
  Dlg: TOpenDialog;
begin

  if ListBox1.ItemIndex >= 0 then
    BackupFile := ListBox1.Items[ListBox1.ItemIndex]
  else if FileExists(edtBackupFile.Text) then
    BackupFile := edtBackupFile.Text
  else
  begin
    UpdateStatus('请选择要恢复的备份文件', True);
    Exit;
  end;

  if MessageDlg('确认', '确定要恢复窗口布局吗？这将会覆盖当前的布局设置。',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    try
      XMLConfig:=TXMLConfigStorage.Create(BackupFile,True);
      DockMaster.LoadLayoutFromConfig(XMLConfig,true);
      DockMaster.LoadSettingsFromConfig(XMLConfig);
      UpdateStatus('窗口布局恢复成功!', False);
    finally
      XMLConfig.Free;
    end;
  end;
end;

procedure TDockbkFrm.ListBox1Click(Sender: TObject);
begin
  if ListBox1.ItemIndex >= 0 then
  begin
    edtBackupFile.Text := ListBox1.Items[ListBox1.ItemIndex];
    UpdateStatus(edtBackupFile.Text,False);
    // 预览备份内容
    Memo1.Clear;
    try
      Memo1.Lines.LoadFromFile(ListBox1.Items[ListBox1.ItemIndex]);
    except
      on E: Exception do
        UpdateStatus('无法读取文件: ' + E.Message,True);
    end;
  end;
end;

procedure TDockbkFrm.LoadBackupList;
var
  Files: TStringList;
  i: Integer;
begin
  ListBox1.Clear;

  if DirectoryExists(FBackupDir) then
  begin
    Files := TStringList.Create;
    try
      FindAllFiles(Files, FBackupDir, 'dockbackup_*.xml', False);
      Files.Sort;

      for i := Files.Count - 1 downto 0 do  // 从最新到最旧排序
      begin
        ListBox1.Items.Add(Files[i]);
      end;
    finally
      Files.Free;
    end;
  end;
end;

procedure TDockbkFrm.UpdateStatus(const Msg: string; IsError: Boolean);
begin
  lblStatus.Caption := Msg;

  if IsError then
  begin
    lblStatus.Font.Color := clRed;
    lblStatus.Font.Style := [fsBold];
  end
  else
  begin
    lblStatus.Font.Color := clGreen;
    lblStatus.Font.Style := [];
  end;

  Application.ProcessMessages;
end;

end.
