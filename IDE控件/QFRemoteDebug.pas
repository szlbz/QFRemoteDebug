{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit QFRemoteDebug;

{$warn 5023 off : no warning about unused units}
interface

uses
  QFRemoteDebugunit, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('QFRemoteDebugunit', @QFRemoteDebugunit.Register);
end;

initialization
  RegisterPackage('QFRemoteDebug', @Register);
end.
