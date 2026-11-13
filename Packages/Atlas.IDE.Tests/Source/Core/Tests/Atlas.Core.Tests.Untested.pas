unit Atlas.Core.Tests.Untested;

// Ungetestete Methoden (#1783) ohne VCL und Open Tools API:
// - Marke „7 von 12 Methoden getestet“ an der unit-Zeile: Zeile des
//   unit-Kopfs, gezeigt nur mit Testunit und Methoden; gelb unter
//   tests.untested.warnPercent, sonst grau.
// - Befehl „Ungetestete Methoden des Projekts“: Anfrage
//   atlas/untestedMethods, Antwort lesen und die Units nach der Zahl der
//   ungetesteten Methoden ordnen (die meisten zuerst).
// Gezählt werden Methoden, die mindestens ein Test aufruft; das ist keine
// Abdeckungsmessung.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin;

type
  TAtlasUntestedMethod = record
    /// <summary>TFoo.Bar bzw. Bar.</summary>
    Name: string;
    /// <summary>Name im Kopf des Rumpfs, 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
  end;

  TAtlasUntestedUnit = record
    FileName: string;
    UnitName: string;
    HasTestUnit: Boolean;
    Tested: Integer;
    Total: Integer;
    Untested: TArray<TAtlasUntestedMethod>;
  end;

  TAtlasUntestedProject = record
    /// <summary>Die meisten ungetesteten Methoden zuerst.</summary>
    Units: TArray<TAtlasUntestedUnit>;
    /// <summary>Units, die die Zeitgrenze des Servers nicht mehr erreichte.</summary>
    Skipped: Integer;
    /// <summary>Der Server stieß an eine Grenze: Es können Tests fehlen.</summary>
    Incomplete: Boolean;
    /// <summary>Summe der ungetesteten Methoden.</summary>
    function UntestedCount: Integer;
  end;

  TAtlasUntested = class
  public const
    cProjectMethod = 'atlas/untestedMethods';
  public
    /// <summary>Marke an der unit-Zeile zeigen? Plugin an, „Tests ausführen“ und codeLens.untested.</summary>
    class function Wanted(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>0-basierte Zeile des unit-Kopfs in AText (erstes Wort „unit“ einer Zeile außerhalb von
    /// Kommentaren); -1 ohne.</summary>
    class function UnitLine(const AText: string): Integer; static;
    /// <summary>Marke zeigen? Nur mit Testunit und mindestens einer Methode.</summary>
    class function Shown(AHasTestUnit: Boolean; ATotal: Integer): Boolean; static;
    /// <summary>Gelb? Anteil ATested von ATotal unter AWarnPercent Prozent.</summary>
    class function Warn(ATested, ATotal, AWarnPercent: Integer): Boolean; static;
    /// <summary>Parameter von atlas/untestedMethods: Projekt der Datei AUri, Tiefe und private Methoden.</summary>
    class function ProjectParams(const AUri: string; ADepth: Integer; APrivate: Boolean): string; static;
    /// <summary>Antwort lesen, Units geordnet; False, wenn sie kein Objekt ist. AUriToPath macht aus einer URI den
    /// Pfad.</summary>
    class function FromJson(const AJson: string; const AUriToPath: TFunc<string, string>;
      out AProject: TAtlasUntestedProject): Boolean; static;
    /// <summary>Units mit ungetesteten Methoden, die meisten zuerst; bei Gleichstand nach Name.</summary>
    class function Sorted(const AUnits: TArray<TAtlasUntestedUnit>): TArray<TAtlasUntestedUnit>; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines;

const
  cPercent = 100;

{ TAtlasUntestedProject }

function TAtlasUntestedProject.UntestedCount: Integer;
var
  mUnit: TAtlasUntestedUnit;
begin
  Result := 0;
  for mUnit in Units do
  begin
    Inc(Result, Length(mUnit.Untested));
  end;
end;

{ TAtlasUntested }

class function TAtlasUntested.Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.TestRun and ASettings.CodeLensUntested;
end;

/// <summary>Rest der Zeile ALine nach Kommentaren; AInBrace/AInParen tragen offene Blockkommentare weiter.
/// </summary>
function CodeOf(const ALine: string; var AInBrace, AInParen: Boolean): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := 1;
  while mIndex <= Length(ALine) do
  begin
    if AInBrace then
    begin
      AInBrace := ALine[mIndex] <> '}';
    end
    else if AInParen then
    begin
      if (ALine[mIndex] = '*') and (mIndex < Length(ALine)) and (ALine[mIndex + 1] = ')') then
      begin
        AInParen := False;
        Inc(mIndex);
      end;
    end
    else if ALine[mIndex] = '{' then
    begin
      AInBrace := True;
    end
    else if (ALine[mIndex] = '(') and (mIndex < Length(ALine)) and (ALine[mIndex + 1] = '*') then
    begin
      AInParen := True;
      Inc(mIndex);
    end
    else if (ALine[mIndex] = '/') and (mIndex < Length(ALine)) and (ALine[mIndex + 1] = '/') then
    begin
      Break;
    end
    else
    begin
      Result := Result + ALine[mIndex];
    end;
    Inc(mIndex);
  end;
end;

class function TAtlasUntested.UnitLine(const AText: string): Integer;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mInBrace, mInParen: Boolean;
  mCode: string;
begin
  mLines := TTextLines.SplitLines(AText);
  // Byte-Order-Mark vor dem unit-Kopf.
  if (Length(mLines) > 0) and mLines[0].StartsWith(#$FEFF) then
  begin
    mLines[0] := Copy(mLines[0], 2, MaxInt);
  end;
  mInBrace := False;
  mInParen := False;
  for mIndex := 0 to High(mLines) do
  begin
    mCode := LowerCase(Trim(CodeOf(mLines[mIndex], mInBrace, mInParen)));
    if mCode = '' then
    begin
      Continue;
    end;
    // Das erste Wort außerhalb von Kommentaren entscheidet: unit oder etwas anderes (program, library).
    if (mCode = 'unit') or mCode.StartsWith('unit ') or mCode.StartsWith('unit'#9) then
    begin
      Exit(mIndex);
    end;
    Break;
  end;
  Result := -1;
end;

class function TAtlasUntested.Shown(AHasTestUnit: Boolean; ATotal: Integer): Boolean;
begin
  Result := AHasTestUnit and (ATotal > 0);
end;

class function TAtlasUntested.Warn(ATested, ATotal, AWarnPercent: Integer): Boolean;
begin
  Result := (ATotal > 0) and (Int64(ATested) * cPercent < Int64(AWarnPercent) * ATotal);
end;

class function TAtlasUntested.ProjectParams(const AUri: string; ADepth: Integer; APrivate: Boolean): string;
var
  mParams, mDocument: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    mDocument := TJSONObject.Create;
    mDocument.AddPair('uri', AUri);
    mParams.AddPair('textDocument', mDocument);
    mParams.AddPair('depth', TJSONNumber.Create(ADepth));
    mParams.AddPair('includePrivate', TJSONBool.Create(APrivate));
    Result := mParams.ToJSON;
  finally
    mParams.Free;
  end;
end;

function MethodOf(AEntry: TJSONObject): TAtlasUntestedMethod;
begin
  Result := Default(TAtlasUntestedMethod);
  Result.Name := AEntry.GetValue<string>('name', '');
  Result.Line := AEntry.GetValue<Integer>('line', 0);
  Result.Character := AEntry.GetValue<Integer>('character', 0);
end;

function UnitOf(AEntry: TJSONObject; const AUriToPath: TFunc<string, string>): TAtlasUntestedUnit;
var
  mMethods: TJSONArray;
  mItem: TJSONValue;
begin
  Result := Default(TAtlasUntestedUnit);
  Result.FileName := AEntry.GetValue<string>('uri', '');
  if Assigned(AUriToPath) then
  begin
    Result.FileName := AUriToPath(Result.FileName);
  end;
  Result.UnitName := AEntry.GetValue<string>('unit', '');
  Result.HasTestUnit := AEntry.GetValue<Boolean>('hasTestUnit', False);
  Result.Tested := AEntry.GetValue<Integer>('tested', 0);
  Result.Total := AEntry.GetValue<Integer>('total', 0);
  if not AEntry.TryGetValue<TJSONArray>('untested', mMethods) then
  begin
    Exit;
  end;
  for mItem in mMethods do
  begin
    if mItem is TJSONObject then
    begin
      Result.Untested := Result.Untested + [MethodOf(TJSONObject(mItem))];
    end;
  end;
end;

class function TAtlasUntested.FromJson(const AJson: string; const AUriToPath: TFunc<string, string>;
  out AProject: TAtlasUntestedProject): Boolean;
var
  mValue, mItem: TJSONValue;
  mRoot: TJSONObject;
  mUnits, mLimits: TJSONArray;
  mFound: TArray<TAtlasUntestedUnit>;
begin
  AProject := Default(TAtlasUntestedProject);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    AProject.Skipped := mRoot.GetValue<Integer>('skipped', 0);
    if mRoot.TryGetValue<TJSONArray>('limits', mLimits) then
    begin
      AProject.Incomplete := mLimits.Count > 0;
    end;
    mFound := nil;
    if mRoot.TryGetValue<TJSONArray>('units', mUnits) then
    begin
      for mItem in mUnits do
      begin
        if mItem is TJSONObject then
        begin
          mFound := mFound + [UnitOf(TJSONObject(mItem), AUriToPath)];
        end;
      end;
    end;
    AProject.Units := Sorted(mFound);
  finally
    mValue.Free;
  end;
end;

class function TAtlasUntested.Sorted(const AUnits: TArray<TAtlasUntestedUnit>): TArray<TAtlasUntestedUnit>;
var
  mUnit: TAtlasUntestedUnit;
begin
  Result := nil;
  for mUnit in AUnits do
  begin
    if Length(mUnit.Untested) > 0 then
    begin
      Result := Result + [mUnit];
    end;
  end;
  // TArray.Sort ist nicht stabil: bei Gleichstand nach Unit und Datei weiter.
  TArray.Sort<TAtlasUntestedUnit>(Result, TComparer<TAtlasUntestedUnit>.Construct(
    function(const ALeft, ARight: TAtlasUntestedUnit): Integer
    begin
      Result := Length(ARight.Untested) - Length(ALeft.Untested);
      if Result = 0 then
      begin
        Result := CompareText(ALeft.UnitName, ARight.UnitName);
      end;
      if Result = 0 then
      begin
        Result := CompareText(ALeft.FileName, ARight.FileName);
      end;
    end));
end;

end.
