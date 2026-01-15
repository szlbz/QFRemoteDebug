program QFRemoteDebugServer;

{$MODE objfpc}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils,
  crt,
  DateUtils,
  ServerUnit1 in 'ServerUnit1.pas';

var
  Ch: Char;
  Running: Boolean = True;
  LastStatusCheck: TDateTime;

begin
  try
    if ParamCount>0 then
      eServerPort:=ParamStr(1)
    else
      eServerPort:='8080';

    WriteLn('==========================================');
    WriteLn('QF远程调试服务器 v1.0 (线程模式)');
    WriteLn('==========================================');

    // 启动服务器
    StartServer;

    // 显示状态信息
    WriteLn('');
    WriteLn('服务器正在运行...');
    WriteLn('命令菜单:');
    WriteLn('  S - 显示服务器状态');
    WriteLn('  R - 重启服务器');
    WriteLn('  ESC - 退出服务器');
    WriteLn('');

    LastStatusCheck := Now;

    // 主循环
    while Running do
    begin
      // 每分钟自动显示一次状态
      if MinutesBetween(Now, LastStatusCheck) >= 1 then
      begin
        Write( #27'[2K', FormatDateTime('hh:nn:ss', Now) + ' -服务器运行中...  Server IP: '+GetLocalIP+':'+eServerPort, #13);
        LastStatusCheck := Now;
      end;

      // 处理键盘输入
      if KeyPressed then
      begin
        Ch := ReadKey;
        case Ch of
          #27: // ESC键
            begin
              WriteLn('正在退出服务器...');
              Running := False;
            end;
          's', 'S':
            begin
              WriteLn('');
              WriteLn('=== 服务器状态 ===');
              WriteLn('当前时间: ', FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
              WriteLn('Server IP: ', GetLocalIP);
              WriteLn('监听端口: ', eServerPort);
              WriteLn('');
            end;
          'r', 'R':
            begin
              WriteLn(#13);
              WriteLn('重启服务器...');
              StopServer;
              StartServer;
            end;
        end;
      end;

      // 短暂休眠
      Sleep(100);
    end;

    // 停止服务器
    StopServer;

    WriteLn(#13);
    WriteLn('程序退出');

  except
    on E: Exception do
    begin
      WriteLn(#13);
      WriteLn('程序异常: ', E.Message);
      WriteLn('按任意键退出...');
      ReadKey;
    end;
  end;
end.
