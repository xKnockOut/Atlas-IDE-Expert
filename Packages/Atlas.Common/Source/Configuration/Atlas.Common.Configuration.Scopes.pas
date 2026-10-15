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
// gefiltert. Die Zuordnung erzeugt Tools/Update-ConfigDoc.ps1 aus x-scope im
// Schema (Internals.ScopeData).
// Effective setzt die Ebenen zusammen: global < Editor < Projekt. Die
// Editor-Ebene (initializationOptions und didChangeConfiguration) zählt wie
// global.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Unknown: Schlüssel, den das Schema nicht kennt; der Parser meldet ihn selbst.</summary>
  TConfigurationScope = (Unknown, Global, Project);
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
    /// Originaltext. Ohne solche Schlüssel, bei leerem oder ungültigem Text genau AText.</summary>
    class function Filter(const AText: string; AKeep: TConfigurationScope;
      out AIssues: TArray<TConfigurationIssue>): string; overload; static;
    class function Filter(const AText: string; AKeep: TConfigurationScope): string; overload; static;
    /// <summary>Wirksamer Text aus globaler Datei, Editor-Einstellungen und atlas.json, jeweils auf ihren
    /// Ort gefiltert; je Schlüssel gilt die oberste Ebene, Objekte werden je Glied zusammengeführt.</summary>
    class function Effective(const AGlobalText, AEditorText, AProjectText: string): string; static;
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
  Atlas.Text.Lines;

function Listed(const APath: string; const AList: array of string): Boolean;
var
  Item: string;
begin
  for Item in AList do
    if Item = APath then
      Exit(True);
  Result := False;
end;

function QuoteKey(const AKey: string): string;
var
  Ch: Char;
begin
  Result := '"';
  for Ch in AKey do
    if (Ch = '"') or (Ch = '\') then
      Result := Result + '\' + Ch
    else if Ord(Ch) < 32 then
      Result := Result + Format('\u%.4x', [Ord(Ch)])
    else
      Result := Result + Ch;
  Result := Result + '"';
end;

function NodeText(const AText: string; ANode: TJsonNode): string;
begin
  Result := Copy(AText, ANode.Start + 1, ANode.Stop - ANode.Start);
end;

function Misplaced(const APath: string; AKeep: TConfigurationScope): string;
begin
  if AKeep = TConfigurationScope.Project then
    Result := Format('"%s" gilt für alle Projekte und gehört in die globalen Einstellungen ' +
      '(Tools › Optionen › Atlas, Datei %%APPDATA%%\Atlas\settings.json); in atlas.json wird es ignoriert', [APath])
  else
    Result := Format('"%s" gehört zum Projekt (atlas.json, Atlas › Projekt-Einstellungen); in den globalen ' +
      'Einstellungen wird es ignoriert', [APath]);
end;

{ TConfigurationScopes }

class function TConfigurationScopes.ScopeOf(const APath: string): TConfigurationScope;
var
  Dot: Integer;
begin
  if Listed(APath, GlobalSettingPaths) then
    Exit(TConfigurationScope.Global);
  if Listed(APath, ProjectSettingPaths) then
    Exit(TConfigurationScope.Project);
  Dot := Pos('.', APath);
  if Dot > 0 then
    Exit(ScopeOf(Copy(APath, 1, Dot - 1)));
  Result := TConfigurationScope.Unknown;
end;

class function TConfigurationScopes.IsMixed(const AKey: string): Boolean;
var
  Item: string;
begin
  Result := False;
  for Item in GlobalSettingPaths do
    if Item.StartsWith(AKey + '.') then
      Result := True;
  for Item in ProjectSettingPaths do
    if Item.StartsWith(AKey + '.') then
      Result := True;
end;

class function TConfigurationScopes.Filter(const AText: string; AKeep: TConfigurationScope;
  out AIssues: TArray<TConfigurationIssue>): string;
var
  Root, Value: TJsonNode;
  Index, Sub: Integer;
  Key, Path: string;
  Parts, Members: TArray<string>;
  Removed, SubRemoved: Boolean;
  Scope: TConfigurationScope;

  procedure Report(AKeyStart: Integer; const AKeyText, APath: string);
  var
    Issue: TConfigurationIssue;
  begin
    Issue.Range := TTextRange.Create(TLineTable.Build(AText).PositionAt(AKeyStart),
      TLineTable.Build(AText).PositionAt(AKeyStart + Length(AKeyText) + 2));
    Issue.Message := Misplaced(APath, AKeep);
    Issue.IsError := False;
    AIssues := AIssues + [Issue];
  end;

  function Keeps(AScope: TConfigurationScope): Boolean;
  begin
    Result := (AScope = TConfigurationScope.Unknown) or (AScope = AKeep);
  end;

begin
  AIssues := nil;
  Result := AText;
  if Trim(AText) = '' then
    Exit;
  try
    Root := TJsonTree.Parse(AText);
  except
    // Syntaxfehler meldet der Parser.
    on EJsonTreeError do
      Exit;
  end;
  try
    if Root.Kind <> TJsonKind.Object_ then
      Exit;
    Parts := nil;
    Removed := False;
    for Index := 0 to Root.Count - 1 do
    begin
      Key := Root.Keys[Index];
      Value := Root[Index];
      if IsMixed(Key) and (Value.Kind = TJsonKind.Object_) then
      begin
        Members := nil;
        SubRemoved := False;
        for Sub := 0 to Value.Count - 1 do
        begin
          Path := Key + '.' + Value.Keys[Sub];
          if Keeps(ScopeOf(Path)) then
            Members := Members + [QuoteKey(Value.Keys[Sub]) + ': ' + NodeText(AText, Value[Sub])]
          else
          begin
            Report(Value.KeyStarts[Sub], Value.Keys[Sub], Path);
            SubRemoved := True;
          end;
        end;
        if not SubRemoved then
          Parts := Parts + [QuoteKey(Key) + ': ' + NodeText(AText, Value)]
        else
        begin
          Removed := True;
          // Ein leeres Objekt wäre an diesem Ort sinnlos; es fällt ganz weg.
          if Length(Members) > 0 then
            Parts := Parts + [QuoteKey(Key) + ': {' + string.Join(', ', Members) + '}'];
        end;
        Continue;
      end;
      Scope := TConfigurationScope.Unknown;
      if Key <> '$schema' then
        Scope := ScopeOf(Key);
      if Keeps(Scope) then
        Parts := Parts + [QuoteKey(Key) + ': ' + NodeText(AText, Value)]
      else
      begin
        Report(Root.KeyStarts[Index], Key, Key);
        Removed := True;
      end;
    end;
    if Removed then
      Result := '{' + string.Join(', ', Parts) + '}';
  finally
    Root.Free;
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
  Result := TConfigurationParser.MergeText(TConfigurationParser.MergeText(
    Filter(AGlobalText, TConfigurationScope.Global), Filter(AEditorText, TConfigurationScope.Global)),
    Filter(AProjectText, TConfigurationScope.Project));
end;

class function TConfigurationScopes.GlobalFile(const AAppData: string): string;
begin
  Result := '';
  if AAppData <> '' then
    Result := IncludeTrailingPathDelimiter(AAppData) + GlobalFolder + PathDelim + GlobalName;
end;

end.
