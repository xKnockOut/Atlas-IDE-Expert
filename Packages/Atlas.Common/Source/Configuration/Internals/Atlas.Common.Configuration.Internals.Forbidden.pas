unit Atlas.Common.Configuration.Internals.Forbidden;

// Sperre für Zugangsdaten und absolute Pfade in atlas.json (#486): Die Datei
// liegt im Repository und gilt für alle im Team (wie die Projektdatei .atlas
// des Plugins). Strip entfernt beim Lesen
// - jeden Schlüssel, unter dem Zugangsdaten stehen (token, password, user …,
//   TTextCheckin.IsCredentialKey), auf jeder Ebene,
// - jeden String, der eine Adresse mit Zugangsdaten ist (https://user:pw@…,
//   ?token=…),
// - absolute Pfade (Laufwerk, UNC) in den Pfad-Einstellungen des Projekts:
//   project, testUnits.folder, testUnits.project, exclude, index.exclude und
//   overrides[].files. Glob-Muster ab dem Projektordner ("/Generated/**")
//   bleiben erlaubt.
// und meldet jeden Fund als Warnung mit Position. Relative Pfade, die aus dem
// Ordner herausführen ("..\Tests"), bleiben erlaubt: atlas.json liegt oft
// neben der .dproj in einem Unterordner des Repositorys. Die globale Datei
// %APPDATA%\Atlas\settings.json ist persönlich und wird nicht gefiltert.

interface

uses
  Atlas.Common.Configuration.Contract;

type
  TForbiddenEntries = class
  public
    /// <summary>AText ohne verbotene Einträge; AIssues nennt jeden (Warnung) mit Position in AText. Ohne Fund,
    /// bei leerem oder ungültigem Text genau AText.</summary>
    class function Strip(const AText: string; out AIssues: TArray<TConfigurationIssue>): string; static;
    /// <summary>Pfad-Einstellung, in der ein absoluter Pfad verboten ist ("project", "exclude[]",
    /// "overrides[].files[]" …).</summary>
    class function IsPathSetting(const APath: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Lines,
  Atlas.Text.Checkin,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Internals.JsonTree;

const
  PathSettings: array[0..5] of string = ('project', 'testUnits.folder', 'testUnits.project', 'exclude[]',
    'index.exclude[]', 'overrides[].files[]');

type
  TStripper = class
  private
    FText: string;
    FLines: TLineTable;
    FIssues: TArray<TConfigurationIssue>;
    procedure Report(AStart, AStop: Integer; const AMessage: string);
    function NodeText(ANode: TJsonNode): string;
    /// <summary>Text des Knotens ohne verbotene Teile; AChanged, wenn etwas fehlt.</summary>
    function Rebuild(ANode: TJsonNode; const APath: string; out AChanged: Boolean): string;
    /// <summary>Ist der Wert selbst verboten (String mit Zugangsdaten oder absolutem Pfad)?</summary>
    function Forbidden(ANode: TJsonNode; const APath: string): Boolean;
  public
    constructor Create(const AText: string);
    function Run: string;
    property Issues: TArray<TConfigurationIssue> read FIssues;
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

function Join(const APath, AKey: string): string;
begin
  if APath = '' then
    Exit(AKey);
  Result := APath + '.' + AKey;
end;

{ TStripper }

constructor TStripper.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FLines := TLineTable.Build(AText);
end;

procedure TStripper.Report(AStart, AStop: Integer; const AMessage: string);
var
  Issue: TConfigurationIssue;
begin
  Issue.Range := TTextRange.Create(FLines.PositionAt(AStart), FLines.PositionAt(AStop));
  Issue.Message := AMessage;
  Issue.IsError := False;
  FIssues := FIssues + [Issue];
end;

function TStripper.NodeText(ANode: TJsonNode): string;
begin
  Result := Copy(FText, ANode.Start + 1, ANode.Stop - ANode.Start);
end;

function TStripper.Forbidden(ANode: TJsonNode; const APath: string): Boolean;
var
  Shown: string;
begin
  Result := False;
  if ANode.Kind <> TJsonKind.String_ then
    Exit;
  Shown := StringReplace(APath, '[]', '', [rfReplaceAll]);
  if TTextCheckin.HasUrlCredentials(ANode.Value) then
  begin
    Report(ANode.Start, ANode.Stop, Format('"%s" enthält Zugangsdaten in der Adresse; atlas.json gilt für alle ' +
      'im Team, der Wert wird ignoriert', [Shown]));
    Exit(True);
  end;
  if TForbiddenEntries.IsPathSetting(APath) and TTextCheckin.IsMachinePath(ANode.Value) then
  begin
    Report(ANode.Start, ANode.Stop, Format('"%s": absolute Pfade gehören nicht in atlas.json (gilt für alle im ' +
      'Team); der Wert wird ignoriert, bitte relativ zum Projektordner angeben', [Shown]));
    Exit(True);
  end;
end;

function TStripper.Rebuild(ANode: TJsonNode; const APath: string; out AChanged: Boolean): string;
var
  Index: Integer;
  Key, Path, Child: string;
  Parts: TArray<string>;
  ChildChanged: Boolean;
begin
  AChanged := False;
  Parts := nil;
  if ANode.Kind = TJsonKind.Object_ then
  begin
    for Index := 0 to ANode.Count - 1 do
    begin
      Key := ANode.Keys[Index];
      Path := Join(APath, Key);
      if TTextCheckin.IsCredentialKey(Key) then
      begin
        Report(ANode.KeyStarts[Index], ANode.KeyStarts[Index] + Length(Key) + 2, Format('"%s" sieht nach ' +
          'Zugangsdaten aus; die gehören nicht in atlas.json (gilt für alle im Team, Anmeldespeicher von Windows ' +
          'verwenden) und werden ignoriert', [Path]));
        AChanged := True;
        Continue;
      end;
      if Forbidden(ANode[Index], Path) then
      begin
        AChanged := True;
        Continue;
      end;
      Child := Rebuild(ANode[Index], Path, ChildChanged);
      if ChildChanged then
        AChanged := True;
      Parts := Parts + [QuoteKey(Key) + ': ' + Child];
    end;
    if not AChanged then
      Exit(NodeText(ANode));
    Exit('{' + string.Join(', ', Parts) + '}');
  end;
  if ANode.Kind = TJsonKind.Array_ then
  begin
    Path := APath + '[]';
    for Index := 0 to ANode.Count - 1 do
    begin
      if Forbidden(ANode[Index], Path) then
      begin
        AChanged := True;
        Continue;
      end;
      Child := Rebuild(ANode[Index], Path, ChildChanged);
      if ChildChanged then
        AChanged := True;
      Parts := Parts + [Child];
    end;
    if not AChanged then
      Exit(NodeText(ANode));
    Exit('[' + string.Join(', ', Parts) + ']');
  end;
  Result := NodeText(ANode);
end;

function TStripper.Run: string;
var
  Root: TJsonNode;
  Changed: Boolean;
begin
  Result := FText;
  if Trim(FText) = '' then
    Exit;
  try
    Root := TJsonTree.Parse(FText);
  except
    // Syntaxfehler meldet der Parser.
    on EJsonTreeError do
      Exit;
  end;
  try
    if Root.Kind <> TJsonKind.Object_ then
      Exit;
    Result := Rebuild(Root, '', Changed);
    if not Changed then
      Result := FText;
  finally
    Root.Free;
  end;
end;

{ TForbiddenEntries }

class function TForbiddenEntries.IsPathSetting(const APath: string): Boolean;
var
  Item: string;
begin
  for Item in PathSettings do
    if Item = APath then
      Exit(True);
  Result := False;
end;

class function TForbiddenEntries.Strip(const AText: string; out AIssues: TArray<TConfigurationIssue>): string;
var
  Stripper: TStripper;
begin
  Stripper := TStripper.Create(AText);
  try
    Result := Stripper.Run;
    AIssues := Stripper.Issues;
  finally
    Stripper.Free;
  end;
end;

end.
