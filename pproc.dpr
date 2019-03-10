program pproc;

uses
  madExcept,
  madLinkDisAsm,
  madListHardware,
  madListProcesses,
  madListModules,
  Vcl.Forms,
  Misc,
  Windows,
  UIDialog in 'UIDialog.pas' {MainForm},
  PhotonFile in 'PhotonFile.pas';

{$R *.res}

begin
  StartLogging('');
  ShowConsole(SW_SHOW);
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
