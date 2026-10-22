unit Atlas.Windows.Diagnostics.StackGuard;

// Platform-Feature "Diagnostics", Root: setzt nach einem abgefangenen
// Stapelüberlauf die Schutzseite des Threads neu (#1094). Ohne sie beendet
// Windows den Prozess beim nächsten Überlauf, statt eine EStackOverflow zu
// melden. Die Arbeit macht _resetstkoflw der C-Laufzeit (msvcrt.dll); fehlt
// die Funktion, bleibt alles wie bisher.

interface

type
  TWindowsStackGuard = record
  public
    /// <summary>Trägt die Wiederherstellung in TStackGuard.Restore ein.</summary>
    class procedure Install; static;
    /// <summary>Nimmt sie wieder heraus.</summary>
    class procedure Uninstall; static;
    /// <summary>Setzt die Schutzseite des aktuellen Threads neu; False, wenn das nicht ging.</summary>
    class function ResetGuardPage: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Common.Diagnostics.StackGuard;

type
  TResetStackOverflow = function: Integer; cdecl;

var
  ResetFunction: TResetStackOverflow;
  Looked: Boolean;

class function TWindowsStackGuard.ResetGuardPage: Boolean;
var
  Module: HMODULE;
begin
  if not Looked then
  begin
    Module := LoadLibrary('msvcrt.dll');
    if Module <> 0 then
      @ResetFunction := GetProcAddress(Module, '_resetstkoflw');
    Looked := True;
  end;
  Result := Assigned(ResetFunction) and (ResetFunction() <> 0);
end;

class procedure TWindowsStackGuard.Install;
begin
  TStackGuard.Restore :=
    procedure
    begin
      ResetGuardPage;
    end;
end;

class procedure TWindowsStackGuard.Uninstall;
begin
  TStackGuard.Restore := nil;
end;

end.
