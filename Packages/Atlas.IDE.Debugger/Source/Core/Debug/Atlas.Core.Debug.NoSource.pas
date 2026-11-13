unit Atlas.Core.Debug.NoSource;

// Fenster „Kein Quelltext“ (#869), ohne IDE: Hält der Debugger in einer
// Routine ohne Quelltext, ermittelt Atlas den Grund und die Auswege.
// - TAtlasNoSourcePlace liest die Kopfzeile des obersten Rahmens, wie das
//   Fenster Aufrufstack der IDE sie zeigt: ":76F3A2B0 KERNELBASE.RaiseException
//   + 0x62" (Adresse, Modul, Routine) oder "System.SysUtils.FormatFloat(…)".
//   UnitCandidates nennt die möglichen Units, die längste zuerst
//   ("Vcl.Forms.TCustomForm.Show" → "Vcl.Forms.TCustomForm", "Vcl.Forms", "Vcl").
// - TAtlasNoSourceFacts sammelt, was die IDE-Schicht findet: Modul im
//   Windows-Ordner, DCU und PAS in Such- und Bibliothekspfaden, DCU aus der
//   Bibliothek von Delphi, Debug-DCUs, {$D-} im Quelltext.
// - Decide wählt den Grund, Ways die Auswege dazu.
// - Liste der Units ohne Fenster (debug.noSourcePage.ignoredUnits): durch „;“
//   oder „,“ getrennt, Groß-/Kleinschreibung egal.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TAtlasNoSourceReason = (DebugDcusOff, NoDebugInfo, DcuOnly, NotInSearchPath, SystemCode);
  TAtlasNoSourceWay = (EnableDebugDcus, ReturnToOwnCode, FindSource, KeepCpu);
  {$SCOPEDENUMS OFF}
  TAtlasNoSourceWays = set of TAtlasNoSourceWay;

  /// <summary>Ort ohne Quelltext aus der Kopfzeile eines Rahmens.</summary>
  TAtlasNoSourcePlace = record
    /// <summary>Adresse ohne Doppelpunkt ("76F3A2B0"); '' ohne.</summary>
    Address: string;
    /// <summary>Erster Teil vor dem Punkt, wenn die Zeile mit einer Adresse beginnt ("KERNELBASE"); '' sonst.
    /// </summary>
    Module: string;
    /// <summary>Routine ohne Parameter und Versatz ("System.SysUtils.FormatFloat").</summary>
    Routine: string;
    class function Parse(const AHeader: string): TAtlasNoSourcePlace; static;
    /// <summary>Mögliche Units der Routine, die längste zuerst; ohne Punkt keine.</summary>
    function UnitCandidates: TArray<string>;
  end;

  TAtlasNoSourceFacts = record
    Place: TAtlasNoSourcePlace;
    /// <summary>Gefundene Unit (aus UnitCandidates); '' ohne.</summary>
    UnitName: string;
    DcuPath: string;
    PasPath: string;
    /// <summary>Modul liegt im Windows-Ordner (System32 usw.).</summary>
    SystemModule: Boolean;
    /// <summary>DCU stammt aus der Bibliothek von Delphi (RTL, VCL …).</summary>
    LibraryUnit: Boolean;
    /// <summary>DCC_DebugDCUs beim Start.</summary>
    DebugDcus: Boolean;
    /// <summary>Quelltext schaltet die Debug-Informationen ab ({$D-}).</summary>
    DebugInfoOff: Boolean;
  end;

  TAtlasNoSource = record
  public const
    cListSeparators: array[0..1] of Char = (';', ',');
  public
    class function Decide(const AFacts: TAtlasNoSourceFacts): TAtlasNoSourceReason; static;
    /// <summary>Auswege zu AReason; AHasOwnFrame: weiter unten im Stapel steht eigener Code; ADebugConfiguration:
    /// das Projekt hat eine Konfiguration „Debug“.</summary>
    class function Ways(AReason: TAtlasNoSourceReason; AHasOwnFrame, ADebugConfiguration: Boolean): TAtlasNoSourceWays;
      static;
    /// <summary>Schaltet der Quelltext die Debug-Informationen ab ({$D-}, {$DEBUGINFO OFF}, auch in einer Liste
    /// wie {$D-,L-})?</summary>
    class function DebugInfoOff(const ASource: string): Boolean; static;
    /// <summary>Datei AName im ersten Ordner aus AFolders, in dem AExists sie findet; '' ohne.</summary>
    class function FindFile(const AName: string; const AFolders: TArray<string>;
      const AExists: TFunc<string, Boolean>): string; static;
    /// <summary>Unit, DCU und PAS zu APlace in AFolders: die längste Unit, zu der es eine DCU oder PAS gibt.</summary>
    class procedure Locate(const APlace: TAtlasNoSourcePlace; const AFolders: TArray<string>;
      const AExists: TFunc<string, Boolean>; var AFacts: TAtlasNoSourceFacts); static;
    /// <summary>Liegt AFileName unter einem der Ordner AFolders?</summary>
    class function IsUnder(const AFileName: string; const AFolders: TArray<string>): Boolean; static;
    /// <summary>Einträge der Liste, getrimmt, ohne leere.</summary>
    class function Units(const AList: string): TArray<string>; static;
    class function IsIgnored(const AUnit, AList: string): Boolean; static;
    /// <summary>AList mit AUnit (falls noch nicht enthalten), durch „; “ getrennt.</summary>
    class function AddIgnored(const AList, AUnit: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions;

const
  /// <summary>Versatz hinter der Routine: " + 0x62", " + $40".</summary>
  cOffsetPattern = '\s*\+\s*(0x|\$)?[0-9A-Fa-f]+\s*$';
  /// <summary>Adresse am Anfang: ":76F3A2B0 " oder "76F3A2B0 ".</summary>
  cAddressPattern = '^:?([0-9A-Fa-f]{6,16})\s+';
  /// <summary>Schalter D bzw. DEBUGINFO aus in einer Direktive.</summary>
  cDebugOffPattern = '\{\$(?:[A-Z]+[+-]\s*,\s*)*(?:D-|DEBUGINFO\s+OFF)';

{ TAtlasNoSourcePlace }

class function TAtlasNoSourcePlace.Parse(const AHeader: string): TAtlasNoSourcePlace;
var
  mText: string;
  mMatch: TMatch;
  mParen, mDot: Integer;
begin
  Result := Default(TAtlasNoSourcePlace);
  mText := Trim(AHeader);
  mMatch := TRegEx.Match(mText, cAddressPattern);
  if mMatch.Success then
  begin
    Result.Address := UpperCase(mMatch.Groups[1].Value);
    mText := Trim(Copy(mText, mMatch.Length + 1, MaxInt));
  end;
  mParen := Pos('(', mText);
  if mParen > 0 then
  begin
    mText := Copy(mText, 1, mParen - 1);
  end;
  Result.Routine := Trim(TRegEx.Replace(mText, cOffsetPattern, ''));
  mDot := Pos('.', Result.Routine);
  if (Result.Address <> '') and (mDot > 1) then
  begin
    Result.Module := Copy(Result.Routine, 1, mDot - 1);
  end;
end;

function TAtlasNoSourcePlace.UnitCandidates: TArray<string>;
var
  mParts: TArray<string>;
  mCount: Integer;
begin
  Result := nil;
  mParts := Routine.Split(['.']);
  for mCount := Length(mParts) - 1 downto 1 do
  begin
    Result := Result + [string.Join('.', mParts, 0, mCount)];
  end;
end;

{ TAtlasNoSource }

class function TAtlasNoSource.Decide(const AFacts: TAtlasNoSourceFacts): TAtlasNoSourceReason;
begin
  if AFacts.SystemModule then
  begin
    Result := TAtlasNoSourceReason.SystemCode;
  end
  else if (AFacts.DcuPath = '') and (AFacts.PasPath = '') then
  begin
    Result := TAtlasNoSourceReason.NotInSearchPath;
  end
  else if AFacts.LibraryUnit and not AFacts.DebugDcus then
  begin
    Result := TAtlasNoSourceReason.DebugDcusOff;
  end
  else if (AFacts.PasPath <> '') and AFacts.DebugInfoOff then
  begin
    Result := TAtlasNoSourceReason.NoDebugInfo;
  end
  else if AFacts.PasPath = '' then
  begin
    Result := TAtlasNoSourceReason.DcuOnly;
  end
  else
  begin
    // Quelltext vorhanden, aber der Debugger kennt ihn nicht: Ordner fehlt im Suchpfad des Debuggers.
    Result := TAtlasNoSourceReason.NotInSearchPath;
  end;
end;

class function TAtlasNoSource.Ways(AReason: TAtlasNoSourceReason; AHasOwnFrame,
  ADebugConfiguration: Boolean): TAtlasNoSourceWays;
begin
  Result := [TAtlasNoSourceWay.KeepCpu];
  if AHasOwnFrame then
  begin
    Include(Result, TAtlasNoSourceWay.ReturnToOwnCode);
  end;
  case AReason of
    TAtlasNoSourceReason.DebugDcusOff:
      if ADebugConfiguration then
      begin
        Include(Result, TAtlasNoSourceWay.EnableDebugDcus);
      end;
    TAtlasNoSourceReason.DcuOnly, TAtlasNoSourceReason.NotInSearchPath:
      Include(Result, TAtlasNoSourceWay.FindSource);
    TAtlasNoSourceReason.NoDebugInfo, TAtlasNoSourceReason.SystemCode:
      ;
  end;
end;

class function TAtlasNoSource.DebugInfoOff(const ASource: string): Boolean;
begin
  Result := TRegEx.IsMatch(ASource, cDebugOffPattern, [roIgnoreCase]);
end;

class function TAtlasNoSource.FindFile(const AName: string; const AFolders: TArray<string>;
  const AExists: TFunc<string, Boolean>): string;
var
  mFolder, mPath: string;
begin
  Result := '';
  for mFolder in AFolders do
  begin
    if Trim(mFolder) = '' then
    begin
      Continue;
    end;
    mPath := IncludeTrailingPathDelimiter(Trim(mFolder)) + AName;
    if AExists(mPath) then
    begin
      Exit(mPath);
    end;
  end;
end;

class procedure TAtlasNoSource.Locate(const APlace: TAtlasNoSourcePlace; const AFolders: TArray<string>;
  const AExists: TFunc<string, Boolean>; var AFacts: TAtlasNoSourceFacts);
var
  mUnit, mDcu, mPas: string;
begin
  AFacts.Place := APlace;
  for mUnit in APlace.UnitCandidates do
  begin
    mDcu := FindFile(mUnit + '.dcu', AFolders, AExists);
    mPas := FindFile(mUnit + '.pas', AFolders, AExists);
    if (mDcu <> '') or (mPas <> '') then
    begin
      AFacts.UnitName := mUnit;
      AFacts.DcuPath := mDcu;
      AFacts.PasPath := mPas;
      Exit;
    end;
  end;
end;

class function TAtlasNoSource.IsUnder(const AFileName: string; const AFolders: TArray<string>): Boolean;
var
  mFolder: string;
begin
  for mFolder in AFolders do
  begin
    if (Trim(mFolder) <> '') and StartsText(IncludeTrailingPathDelimiter(Trim(mFolder)), AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasNoSource.Units(const AList: string): TArray<string>;
var
  mItem: string;
begin
  Result := nil;
  for mItem in AList.Split(cListSeparators) do
  begin
    if Trim(mItem) <> '' then
    begin
      Result := Result + [Trim(mItem)];
    end;
  end;
end;

class function TAtlasNoSource.IsIgnored(const AUnit, AList: string): Boolean;
begin
  Result := (AUnit <> '') and (IndexText(AUnit, Units(AList)) >= 0);
end;

class function TAtlasNoSource.AddIgnored(const AList, AUnit: string): string;
begin
  if (Trim(AUnit) = '') or IsIgnored(Trim(AUnit), AList) then
  begin
    Exit(string.Join('; ', Units(AList)));
  end;
  Result := string.Join('; ', Units(AList) + [Trim(AUnit)]);
end;

end.
