{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit QFRemoteDebug;

{$warn 5023 off : no warning about unused units}
interface

uses
  QFRemoteDebugunit, QFCompilerRununit,QFRemoteUpdateCrossLibunit, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('QFRemoteDebugunit', @QFRemoteDebugunit.Register);
  RegisterUnit('QFCompilerRununit', @QFCompilerRununit.Register);
  RegisterUnit('QFRemoteUpdateCrossLibunit', @QFRemoteUpdateCrossLibunit.Register);
end;

initialization
  RegisterPackage('QFRemoteDebug', @Register);
end.
