unit Atlas.Common.Dfm.FormFiles;

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
  cViewNames: array[0..10] of string = ('Windows', 'Macintosh', 'Mac', 'Linux', 'Surface', 'LgXhdpiPh',
    'LgXhdpiTb', 'SmXhdpiPh', 'NmXhdpiPh', 'XLgXhdpiTb', 'GoogleGlass');
  cViewPrefixes: array[0..3] of string = ('iPhone', 'iPad', 'iOS', 'Android');

function IsView(const ASegment: string): Boolean;
var
  mPrefix: string;
begin
  Result := IndexText(ASegment, cViewNames) >= 0;
  if not Result then
  begin
    for mPrefix in cViewPrefixes do
    begin
      if StartsText(mPrefix, ASegment) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

class function TFormFiles.UnitFile(const AFormFile: string): string;
var
  mBase, mSegment: string;
begin
  mBase := ChangeFileExt(AFormFile, '');
  if SameText(ExtractFileExt(AFormFile), '.fmx') then
  begin
    mSegment := ExtractFileExt(mBase);
    if (mSegment <> '') and IsView(Copy(mSegment, 2, MaxInt)) then
    begin
      mBase := ChangeFileExt(mBase, '');
    end;
  end;
  Result := mBase + '.pas';
end;

class function TFormFiles.FormFiles(const AUnitFile, AUnitText: string): TArray<string>;

  procedure Add(const AFileName: string);
  begin
    if IndexText(AFileName, Result) < 0 then
    begin
      Result := Result + [AFileName];
    end;
  end;

var
  mAt, mStop: Integer;
  mText, mName, mFolder, mUpper: string;
begin
  Result := nil;
  Add(ChangeFileExt(AUnitFile, '.dfm'));
  Add(ChangeFileExt(AUnitFile, '.fmx'));
  mFolder := ExtractFilePath(AUnitFile);
  mUpper := UpperCase(AUnitText);
  mAt := Pos('{$R ', mUpper);
  while mAt > 0 do
  begin
    mStop := PosEx('}', AUnitText, mAt);
    if mStop = 0 then
    begin
      Break;
    end;
    mText := Trim(Copy(AUnitText, mAt + 4, mStop - mAt - 4));
    if Pos(' ', mText) > 0 then
    begin
      mText := Copy(mText, 1, Pos(' ', mText) - 1);
    end;
    mText := StringReplace(mText, '''', '', [rfReplaceAll]);
    if EndsText('.fmx', mText) then
    begin
      if StartsText('*', mText) then
      begin
        mName := ChangeFileExt(AUnitFile, '') + Copy(mText, 2, MaxInt);
      end
      else
      begin
        mName := mFolder + mText;
      end;
      Add(mName);
    end;
    mAt := PosEx('{$R ', mUpper, mStop);
  end;
end;

end.
