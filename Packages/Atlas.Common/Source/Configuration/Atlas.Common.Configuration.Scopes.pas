unit Atlas.Common.Configuration.Scopes;

// Ort der Einstellungen: Jeder Schlüssel hat genau einen Ort.
// - Global (%APPDATA%\Atlas\settings.json, im Plugin Tools › Optionen › Atlas):
//   persönliche und rechnerbezogene Einstellungen wie Index, Speicher, Hints,
//   Protokoll und Sprache.
// - Projekt (atlas.json im Projektordner): Code und Team, also Prüfregeln,
//   Format, Code-Stil, Konfiguration, Plattform und Ausschlüsse.
// Filter entfernt aus einem Text die Schlüssel des anderen Orts und meldet sie
// als Warnung; ein Schlüssel am falschen Ort wirkt also nicht, auch nicht als
// Überschreibung. Gemischte Objekte (index, completion) werden je Glied
// gefiltert. Ausnahme rules (x-scope "both"): Prüfregeln gelten global für alle
// Projekte, atlas.json übersteuert je Regel (Effective führt Objekte je Glied
// zusammen). Die Zuordnung erzeugt Tools/Update-ConfigDoc.ps1 aus x-scope im
// Schema (Internals.ScopeData).
// Effective setzt die Ebenen zusammen: global < Editor < Projekt. Die
// Editor-Ebene (initializationOptions und didChangeConfiguration) zählt wie
// global.
// atlas.json liegt im Repository und gilt für alle im Team: Filter für den
// Projekt-Ort entfernt zusätzlich Zugangsdaten und absolute Pfade und meldet
// sie (#486, Internals.Forbidden); dieselbe Sperre gilt im Plugin für die
// Projektdatei .atlas.
// Experimentelle Schlüssel (x-experimental, #834) wirken nur mit dem
// Hauptschalter experimental.enabled; ohne ihn entfernt Effective sie aus dem
// zusammengesetzten Text, es gelten ihre Vorgaben. Die Dateien behalten die
// Werte.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Unknown: Schlüssel, den das Schema nicht kennt; der Parser meldet ihn selbst. Both: an beiden
  /// Orten erlaubt (rules), das Projekt übersteuert je Glied.</summary>
  TConfigurationScope = (Unknown, Global, Project, Both);
{$SCOPEDENUMS OFF}

  TConfigurationScopes = class
  public const
    GlobalFolder = 'Atlas';
    GlobalName = 'settings.json';
  public
    /// <summary>Ort eines Schlüssels ("index", "index.exclude", "rules"); ein Glied ohne eigenen Eintrag
    /// erbt den Ort seines Objekts.</summary>
    class function ScopeOf(const APath: string): TConfigurationScope; static;
    /// <summary>Objekt mit Gliedern beider Orte (index, completion).</summary>
    class function IsMixed(const AKey: string): Boolean; static;
    /// <summary>AText ohne die Schlüssel, die nicht nach AKeep gehören; AIssues nennt sie mit Position im
    /// Originaltext. Für den Projekt-Ort fehlen außerdem Zugangsdaten und absolute Pfade (#486), ebenfalls mit
    /// Meldung. Ohne solche Schlüssel, bei leerem oder ungültigem Text genau AText.</summary>
    class function Filter(const AText: string; AKeep: TConfigurationScope;
      out AIssues: TArray<TConfigurationIssue>): string; overload; static;
    class function Filter(const AText: string; AKeep: TConfigurationScope): string; overload; static;
    /// <summary>Wirksamer Text aus globaler Datei, Editor-Einstellungen und atlas.json, jeweils auf ihren
    /// Ort gefiltert; je Schlüssel gilt die oberste Ebene, Objekte werden je Glied zusammengeführt.</summary>
    class function Effective(const AGlobalText, AEditorText, AProjectText: string): string; static;
    /// <summary>Steht in AText "experimental": {"enabled": true}?</summary>
    class function ExperimentalEnabled(const AText: string): Boolean; static;
    /// <summary>Ohne Hauptschalter in AText fallen die Schlüssel aus APaths ("objekt" oder "objekt.glied")
    /// weg, damit ihre Vorgaben gelten (#834). Mit Hauptschalter, ohne solche Schlüssel, bei leerem oder
    /// ungültigem Text genau AText.</summary>
    class function WithoutExperimental(const AText: string; const APaths: TArray<string>): string; static;
    /// <summary>%APPDATA%\Atlas\settings.json; '' ohne AAppData.</summary>
    class function GlobalFile(const AAppData: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Configuration.Internals.ScopeData,
  Atlas.Common.Configuration.Internals.Forbidden,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TScopesText = (AppliesToAllProjectsAnd, BelongsToTheProjectAtlas);

const
  cTexts: array[TScopesText] of TAtlasText = (
    (De: '"%s" gilt für alle Projekte und gehört in die globalen Einstellungen (Tools › Optionen › Atlas, Datei ' +
      '%%APPDATA%%\Atlas\settings.json); in atlas.json wird es ignoriert';
     En: '"%s" applies to all projects and belongs in the global settings (Tools › Options › Atlas, file ' +
      '%%APPDATA%%\Atlas\settings.json); in atlas.json it is ignored'),
    (De: '"%s" gehört zum Projekt (atlas.json, Atlas › Projekt-Einstellungen); in den globalen Einstellungen wird es ' +
      'ignoriert';
     En: '"%s" belongs to the project (atlas.json, Atlas › Project Settings); in the global settings it is ignored'));

{$SCOPEDENUMS OFF}

function Listed(const APath: string; const AList: array of string): Boolean;
var
  Item: string;
begin
  for Item in AList do
  begin
    if Item = APath then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function QuoteKey(const AKey: string): string;
var
  Ch: Char;
begin
  Result := '"';
  for Ch in AKey do
  begin
    if (Ch = '"') or (Ch = '\') then
    begin
      Result := Result + '\' + Ch;
    end
    else if Ord(Ch) < 32 then
    begin
      Result := Result + Format('\u%.4x', [Ord(Ch)]);
    end
    else
    begin
      Result := Result + Ch;
    end;
  end;
  Result := Result + '"';
end;

function NodeText(const AText: string; ANode: TJsonNode): string;
begin
  Result := Copy(AText, ANode.Start + 1, ANode.Stop - ANode.Start);
end;

function Misplaced(const APath: string; AKeep: TConfigurationScope): string;
begin
  if AKeep = TConfigurationScope.Project then
  begin
    Result := cTexts[TScopesText.AppliesToAllProjectsAnd].Fmt([APath]);
  end
  else
  begin
    Result := cTexts[TScopesText.BelongsToTheProjectAtlas].Fmt([APath]);
  end;
end;

function FilterScope(const AText: string; AKeep: TConfigurationScope;
  out AIssues: TArray<TConfigurationIssue>): string; forward;

{ TConfigurationScopes }

class function TConfigurationScopes.ScopeOf(const APath: string): TConfigurationScope;
var
  Dot: Integer;
begin
  if Listed(APath, GlobalSettingPaths) and Listed(APath, ProjectSettingPaths) then
  begin
    Exit(TConfigurationScope.Both);
  end;
  if Listed(APath, GlobalSettingPaths) then
  begin
    Exit(TConfigurationScope.Global);
  end;
  if Listed(APath, ProjectSettingPaths) then
  begin
    Exit(TConfigurationScope.Project);
  end;
  Dot := Pos('.', APath);
  if Dot > 0 then
  begin
    Exit(ScopeOf(Copy(APath, 1, Dot - 1)));
  end;
  Result := TConfigurationScope.Unknown;
end;

class function TConfigurationScopes.IsMixed(const AKey: string): Boolean;
var
  Item: string;
begin
  Result := False;
  for Item in GlobalSettingPaths do
  begin
    if Item.StartsWith(AKey + '.') then
    begin
      Result := True;
    end;
  end;
  for Item in ProjectSettingPaths do
  begin
    if Item.StartsWith(AKey + '.') then
    begin
      Result := True;
    end;
  end;
end;

class function TConfigurationScopes.Filter(const AText: string; AKeep: TConfigurationScope;
  out AIssues: TArray<TConfigurationIssue>): string;
var
  Forbidden, Ignored: TArray<TConfigurationIssue>;
begin
  if AKeep <> TConfigurationScope.Project then
  begin
    Exit(FilterScope(AText, AKeep, AIssues));
  end;
  // atlas.json gilt für alle im Team (#486): ohne Zugangsdaten und absolute Pfade. Die Meldungen zum Ort beziehen
  // sich auf den Originaltext.
  FilterScope(AText, AKeep, AIssues);
  Result := FilterScope(TForbiddenEntries.Strip(AText, Forbidden), AKeep, Ignored);
  AIssues := AIssues + Forbidden;
end;

/// <summary>Wurzelobjekt von AText; nil bei leerem Text, Syntaxfehler (meldet der Parser) oder einer Wurzel,
/// die kein Objekt ist.</summary>
function ParseRootObject(const AText: string): TJsonNode;
begin
  Result := nil;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  try
    Result := TJsonTree.Parse(AText);
  except
    // Syntaxfehler meldet der Parser.
    on EJsonTreeError do
      Exit;
  end;
  if Result.Kind <> TJsonKind.Object_ then
  begin
    FreeAndNil(Result);
  end;
end;

/// <summary>"schlüssel": wert aus dem Originaltext.</summary>
function Member(const AText, AKey: string; AValue: TJsonNode): string;
begin
  Result := QuoteKey(AKey) + ': ' + NodeText(AText, AValue);
end;

type
  /// <summary>Sammelt beim Filtern auf einen Ort die behaltenen Glieder und die Meldungen.</summary>
  TScopeFilter = record
    Text: string;
    Keep: TConfigurationScope;
    Issues: TArray<TConfigurationIssue>;
    Parts: TArray<string>;
    Removed: Boolean;
    procedure Report(AKeyStart: Integer; const AKeyText, APath: string);
    function Keeps(AScope: TConfigurationScope): Boolean;
    procedure AddMixed(const AKey: string; AValue: TJsonNode);
    procedure Add(ARoot: TJsonNode; AIndex: Integer);
  end;

procedure TScopeFilter.Report(AKeyStart: Integer; const AKeyText, APath: string);
var
  mIssue: TConfigurationIssue;
begin
  mIssue.Range := TTextRange.Create(TLineTable.Build(Text).PositionAt(AKeyStart),
    TLineTable.Build(Text).PositionAt(AKeyStart + Length(AKeyText) + 2));
  mIssue.Message := Misplaced(APath, Keep);
  mIssue.IsError := False;
  Issues := Issues + [mIssue];
end;

function TScopeFilter.Keeps(AScope: TConfigurationScope): Boolean;
begin
  Result := (AScope = TConfigurationScope.Unknown) or (AScope = TConfigurationScope.Both) or (AScope = Keep);
end;

procedure TScopeFilter.AddMixed(const AKey: string; AValue: TJsonNode);
var
  mSub: Integer;
  mPath: string;
  mMembers: TArray<string>;
  mSubRemoved: Boolean;
begin
  mMembers := nil;
  mSubRemoved := False;
  for mSub := 0 to AValue.Count - 1 do
  begin
    mPath := AKey + '.' + AValue.Keys[mSub];
    if Keeps(TConfigurationScopes.ScopeOf(mPath)) then
    begin
      mMembers := mMembers + [Member(Text, AValue.Keys[mSub], AValue[mSub])];
    end
    else
    begin
      Report(AValue.KeyStarts[mSub], AValue.Keys[mSub], mPath);
      mSubRemoved := True;
    end;
  end;
  if not mSubRemoved then
  begin
    Parts := Parts + [Member(Text, AKey, AValue)];
  end
  else
  begin
    Removed := True;
    // Ein leeres Objekt wäre an diesem Ort sinnlos; es fällt ganz weg.
    if Length(mMembers) > 0 then
    begin
      Parts := Parts + [QuoteKey(AKey) + ': {' + string.Join(', ', mMembers) + '}'];
    end;
  end;
end;

procedure TScopeFilter.Add(ARoot: TJsonNode; AIndex: Integer);
var
  mKey: string;
  mValue: TJsonNode;
  mScope: TConfigurationScope;
begin
  mKey := ARoot.Keys[AIndex];
  mValue := ARoot[AIndex];
  if TConfigurationScopes.IsMixed(mKey) and (mValue.Kind = TJsonKind.Object_) then
  begin
    AddMixed(mKey, mValue);
    Exit;
  end;
  mScope := TConfigurationScope.Unknown;
  if mKey <> '$schema' then
  begin
    mScope := TConfigurationScopes.ScopeOf(mKey);
  end;
  if Keeps(mScope) then
  begin
    Parts := Parts + [Member(Text, mKey, mValue)];
  end
  else
  begin
    Report(ARoot.KeyStarts[AIndex], mKey, mKey);
    Removed := True;
  end;
end;

function FilterScope(const AText: string; AKeep: TConfigurationScope;
  out AIssues: TArray<TConfigurationIssue>): string;
var
  mRoot: TJsonNode;
  mIndex: Integer;
  mFilter: TScopeFilter;
begin
  AIssues := nil;
  Result := AText;
  mRoot := ParseRootObject(AText);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    mFilter := Default(TScopeFilter);
    mFilter.Text := AText;
    mFilter.Keep := AKeep;
    for mIndex := 0 to mRoot.Count - 1 do
    begin
      mFilter.Add(mRoot, mIndex);
    end;
    AIssues := mFilter.Issues;
    if mFilter.Removed then
    begin
      Result := '{' + string.Join(', ', mFilter.Parts) + '}';
    end;
  finally
    mRoot.Free;
  end;
end;

class function TConfigurationScopes.Filter(const AText: string; AKeep: TConfigurationScope): string;
var
  Ignored: TArray<TConfigurationIssue>;
begin
  Result := Filter(AText, AKeep, Ignored);
end;

class function TConfigurationScopes.Effective(const AGlobalText, AEditorText, AProjectText: string): string;
begin
  Result := WithoutExperimental(TConfigurationParser.MergeText(TConfigurationParser.MergeText(
    Filter(AGlobalText, TConfigurationScope.Global), Filter(AEditorText, TConfigurationScope.Global)),
    Filter(AProjectText, TConfigurationScope.Project)), ExperimentalSettingPaths);
end;

class function TConfigurationScopes.ExperimentalEnabled(const AText: string): Boolean;
var
  Ignored: TArray<TConfigurationIssue>;
begin
  Result := (Trim(AText) <> '') and TConfigurationParser.Parse(AText, Ignored).ExperimentalEnabled;
end;

/// <summary>Objekt AValue ohne die Glieder aus APaths; ARemoved wird gesetzt, wenn eines fehlt.</summary>
function WithoutListedMembers(const AText, AKey: string; AValue: TJsonNode; const APaths: TArray<string>;
  var ARemoved: Boolean): string;
var
  mSub: Integer;
  mMembers: TArray<string>;
  mSubRemoved: Boolean;
begin
  mMembers := nil;
  mSubRemoved := False;
  for mSub := 0 to AValue.Count - 1 do
  begin
    if Listed(AKey + '.' + AValue.Keys[mSub], APaths) then
    begin
      mSubRemoved := True;
    end
    else
    begin
      mMembers := mMembers + [Member(AText, AValue.Keys[mSub], AValue[mSub])];
    end;
  end;
  if not mSubRemoved then
  begin
    Result := Member(AText, AKey, AValue);
  end
  else
  begin
    ARemoved := True;
    Result := QuoteKey(AKey) + ': {' + string.Join(', ', mMembers) + '}';
  end;
end;

class function TConfigurationScopes.WithoutExperimental(const AText: string; const APaths: TArray<string>): string;
var
  mRoot, mValue: TJsonNode;
  mIndex: Integer;
  mKey: string;
  mParts: TArray<string>;
  mRemoved: Boolean;
begin
  Result := AText;
  if (Length(APaths) = 0) or ExperimentalEnabled(AText) then
  begin
    Exit;
  end;
  mRoot := ParseRootObject(AText);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    mParts := nil;
    mRemoved := False;
    for mIndex := 0 to mRoot.Count - 1 do
    begin
      mKey := mRoot.Keys[mIndex];
      mValue := mRoot[mIndex];
      if Listed(mKey, APaths) then
      begin
        mRemoved := True;
      end
      else if mValue.Kind <> TJsonKind.Object_ then
      begin
        mParts := mParts + [Member(AText, mKey, mValue)];
      end
      else
      begin
        mParts := mParts + [WithoutListedMembers(AText, mKey, mValue, APaths, mRemoved)];
      end;
    end;
    if mRemoved then
    begin
      Result := '{' + string.Join(', ', mParts) + '}';
    end;
  finally
    mRoot.Free;
  end;
end;

class function TConfigurationScopes.GlobalFile(const AAppData: string): string;
begin
  Result := '';
  if AAppData <> '' then
  begin
    Result := IncludeTrailingPathDelimiter(AAppData) + GlobalFolder + PathDelim + GlobalName;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Configuration.Scopes', cTexts);

end.
