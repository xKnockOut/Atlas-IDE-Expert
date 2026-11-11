unit Atlas.Core.Tests.UnitMatch;

// Testunits zu einer Unit („Tests dieser Unit ausführen“ in der
// Projektverwaltung, #1817), ohne VCL und Open Tools API. Kandidaten sind die
// Unit selbst (sie kann eine Testunit sein) und Dateien der Projektgruppe mit
// den üblichen Namen: Unit.Tests, UnitTests, Unit.Test, UnitTest, TestUnit,
// Test.Unit (.pas, ohne Rücksicht auf Groß- und Kleinschreibung). Ob ein
// Kandidat Tests enthält, entscheidet der Aufrufer (TDUnitXSource.Scan);
// Names baut daraus die vollen Namen der Fixtures für --run.
// Units und IndexOf liefern die Liste des Assistenten „DUnitX-Testunit zu
// Unit …“ in der Objektgalerie (#1821).

interface

uses
  Atlas.Text.DUnitX;

type
  TAtlasTestUnitMatch = class
  public
    /// <summary>Kandidaten für die Testunits von AUnitFile unter AFiles, AUnitFile zuerst; ohne Doppelte.</summary>
    class function Candidates(const AUnitFile: string; const AFiles: TArray<string>): TArray<string>; static;
    /// <summary>Volle Namen aller Fixtures von AUnit (Unit.Fixture); leer ohne Fixture.</summary>
    class function Names(const AUnit: TDUnitXUnit): TArray<string>; static;
    /// <summary>Die .pas-Dateien von AFiles nach Unitnamen sortiert, ohne Doppelte.</summary>
    class function Units(const AFiles: TArray<string>): TArray<string>; static;
    /// <summary>Stelle von AFileName in AFiles (ohne Rücksicht auf Groß- und Kleinschreibung); -1 ohne.</summary>
    class function IndexOf(const AFiles: TArray<string>; const AFileName: string): Integer; static;
    /// <summary>Unitname zu AFileName (ohne Ordner und Endung).</summary>
    class function UnitNameOf(const AFileName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Defaults,
  System.Generics.Collections;

function BaseName(const AFileName: string): string;
begin
  // Trennzeichen beider Systeme: Die Tests laufen auch unter Linux.
  Result := ChangeFileExt(ExtractFileName(StringReplace(AFileName, '\', '/', [rfReplaceAll])), '');
  Result := Copy(Result, LastDelimiter('/', Result) + 1, MaxInt);
end;

function Matches(const ACandidate, AUnitName: string): Boolean;
var
  mName: string;
begin
  mName := BaseName(ACandidate);
  Result := SameText(mName, AUnitName + '.Tests') or SameText(mName, AUnitName + 'Tests') or
    SameText(mName, AUnitName + '.Test') or SameText(mName, AUnitName + 'Test') or
    SameText(mName, 'Test' + AUnitName) or SameText(mName, 'Test.' + AUnitName);
end;

function Contains(const AFiles: TArray<string>; const AFileName: string): Boolean;
var
  mFile: string;
begin
  for mFile in AFiles do
  begin
    if SameText(mFile, AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasTestUnitMatch.Candidates(const AUnitFile: string; const AFiles: TArray<string>):
  TArray<string>;
var
  mUnitName, mFile: string;
begin
  Result := [AUnitFile];
  mUnitName := BaseName(AUnitFile);
  for mFile in AFiles do
  begin
    if SameText(ExtractFileExt(mFile), '.pas') and Matches(mFile, mUnitName) and not Contains(Result, mFile) then
    begin
      Result := Result + [mFile];
    end;
  end;
end;

class function TAtlasTestUnitMatch.Units(const AFiles: TArray<string>): TArray<string>;
var
  mFile: string;
begin
  Result := nil;
  for mFile in AFiles do
  begin
    if SameText(ExtractFileExt(mFile), '.pas') and not Contains(Result, mFile) then
    begin
      Result := Result + [mFile];
    end;
  end;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const ALeft, ARight: string): Integer
    begin
      Result := CompareText(BaseName(ALeft), BaseName(ARight));
      if Result = 0 then
      begin
        Result := CompareText(ALeft, ARight);
      end;
    end));
end;

class function TAtlasTestUnitMatch.IndexOf(const AFiles: TArray<string>; const AFileName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AFiles) do
  begin
    if SameText(AFiles[mIndex], AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasTestUnitMatch.UnitNameOf(const AFileName: string): string;
begin
  Result := BaseName(AFileName);
end;

class function TAtlasTestUnitMatch.Names(const AUnit: TDUnitXUnit): TArray<string>;
var
  mFixture: TDUnitXFixture;
begin
  Result := nil;
  for mFixture in AUnit.Fixtures do
  begin
    Result := Result + [TDUnitXCommandLine.TestName(AUnit.UnitName, mFixture.Name, '')];
  end;
end;

end.
