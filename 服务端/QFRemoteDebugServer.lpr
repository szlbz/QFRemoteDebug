program QFRemoteDebugServer;

{$MODE objfpc}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Forms, indylaz,
  ServerUnit1 in 'ServerUnit1.pas', Interfaces {Form2};

{$R *.res}

begin
  Application.Scaled:=True;
  Application.Initialize;
  Application.CreateForm(TForm2, Form2);
  Application.Run;
end.
