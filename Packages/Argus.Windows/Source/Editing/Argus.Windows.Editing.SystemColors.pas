unit Argus.Windows.Editing.SystemColors;

// Aktuelle Systemfarben (clBtnFace usw.) für die Farbvorschau (#26).

interface

uses
  Argus.Common.Editing.Colors;

/// <summary>Wert von GetSysColor(AIndex); passt zu TSystemColorProvider.</summary>
function WindowsSystemColor(AIndex: Integer; out AColor: TRgbColor): Boolean;

implementation

uses
  Winapi.Windows;

function WindowsSystemColor(AIndex: Integer; out AColor: TRgbColor): Boolean;
begin
  // GetSysColor liefert wie TColor $00BBGGRR.
  AColor := TRgbColor.FromTColor(GetSysColor(AIndex));
  Result := True;
end;

end.
