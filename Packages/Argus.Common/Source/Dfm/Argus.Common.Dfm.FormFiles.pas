unit Argus.Common.Dfm.FormFiles;

// Zuordnung von Formulardateien und Units (#87). FireMonkey legt Plattformansichten als
// Unit1.Windows.fmx, Unit1.Android.fmx usw. an; sie gehören zu Unit1.pas, nicht zu
// Unit1.Windows.pas. Die Unit bindet sie mit {$R *.Windows.fmx MSWINDOWS} ein.

interface

type
  TFormFiles = class
  public
    /// <summary>Unit zur Formulardatei: Unit1.fmx und Unit1.Windows.fmx → Unit1.pas.</summary>
    class function UnitFile(const AFormFile: string): string; static;
    /// <summary>Formulardateien zur Unit: .dfm, .fmx und die per {$R} eingebundenen Ansichten
    /// (*.Plattform.fmx, name.fmx). AUnitText darf leer sein; ohne Doppelte.</summary>
    class function FormFiles(const AUnitFile, AUnitText: string): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  // Ansichten des FMX-Designers; iPhone…, iPad…, Android… über das Präfix.
  ViewNames: array[0..10] of string = ('Windows', 'Macintosh', 'Mac', 'Linux', 'Surface', 'LgXhdpiPh',
    'LgXhdpiTb', 'SmXhdpiPh', 'NmXhdpiPh', 'XLgXhdpiTb', 'GoogleGlass');
  ViewPrefixes: array[0..3] of string = ('iPhone', 'iPad', 'iOS', 'Android');

function IsView(const ASegment: string): Boolean;
var
  Prefix: string;
begin
  Result := IndexText(ASegment, ViewNames) >= 0;
  if not Result then
    for Prefix in ViewPrefixes do
      if StartsText(Prefix, ASegment) then
        Exit(True);
end;

class function TFormFiles.UnitFile(const AFormFile: string): string;
var
  Base, Segment: string;
begin
  Base := ChangeFileExt(AFormFile, '');
  if SameText(ExtractFileExt(AFormFile), '.fmx') then
  begin
    Segment := ExtractFileExt(Base);
    if (Segment <> '') and IsView(Copy(Segment, 2, MaxInt)) then
      Base := ChangeFileExt(Base, '');
  end;
  Result := Base + '.pas';
end;

class function TFormFiles.FormFiles(const AUnitFile, AUnitText: string): TArray<string>;

  procedure Add(const AFileName: string);
  begin
    if IndexText(AFileName, Result) < 0 then
      Result := Result + [AFileName];
  end;

var
  At, Stop: Integer;
  Text, Name, Folder, Upper: string;
begin
  Result := nil;
  Add(ChangeFileExt(AUnitFile, '.dfm'));
  Add(ChangeFileExt(AUnitFile, '.fmx'));
  Folder := ExtractFilePath(AUnitFile);
  Upper := UpperCase(AUnitText);
  At := Pos('{$R ', Upper);
  while At > 0 do
  begin
    Stop := PosEx('}', AUnitText, At);
    if Stop = 0 then
      Break;
    Text := Trim(Copy(AUnitText, At + 4, Stop - At - 4));
    if Pos(' ', Text) > 0 then
      Text := Copy(Text, 1, Pos(' ', Text) - 1);
    Text := StringReplace(Text, '''', '', [rfReplaceAll]);
    if EndsText('.fmx', Text) then
    begin
      if StartsText('*', Text) then
        Name := ChangeFileExt(AUnitFile, '') + Copy(Text, 2, MaxInt)
      else
        Name := Folder + Text;
      Add(Name);
    end;
    At := PosEx('{$R ', Upper, Stop);
  end;
end;

end.
