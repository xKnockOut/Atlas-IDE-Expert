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
    /// <summary>Glied ohne Verbotenes in AChild; False, wenn das Glied ganz entfällt.</summary>
    function RebuildItem(ANode: TJsonNode; const APath: string; var AChanged: Boolean; out AChild: string): Boolean;
    function RebuildObject(ANode: TJsonNode; const APath: string; out AChanged: Boolean): string;
    function RebuildArray(ANode: TJsonNode; const APath: string; out AChanged: Boolean): string;
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

function Join(const APath, AKey: string): string;
begin
  if APath = '' then
  begin
    Exit(AKey);
  end;
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
  begin
    Exit;
  end;
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

function TStripper.RebuildItem(ANode: TJsonNode; const APath: string; var AChanged: Boolean;
  out AChild: string): Boolean;
var
  mChildChanged: Boolean;
begin
  AChild := '';
  if Forbidden(ANode, APath) then
  begin
    AChanged := True;
    Exit(False);
  end;
  AChild := Rebuild(ANode, APath, mChildChanged);
  if mChildChanged then
  begin
    AChanged := True;
  end;
  Result := True;
end;

function TStripper.RebuildObject(ANode: TJsonNode; const APath: string; out AChanged: Boolean): string;
var
  mIndex: Integer;
  mKey, mPath, mChild: string;
  mParts: TArray<string>;
begin
  AChanged := False;
  mParts := nil;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mKey := ANode.Keys[mIndex];
    mPath := Join(APath, mKey);
    if TTextCheckin.IsCredentialKey(mKey) then
    begin
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2, Format('"%s" sieht nach ' +
        'Zugangsdaten aus; die gehören nicht in atlas.json (gilt für alle im Team, Anmeldespeicher von Windows ' +
        'verwenden) und werden ignoriert', [mPath]));
      AChanged := True;
    end
    else if RebuildItem(ANode[mIndex], mPath, AChanged, mChild) then
    begin
      mParts := mParts + [QuoteKey(mKey) + ': ' + mChild];
    end;
  end;
  Result := NodeText(ANode);
  if AChanged then
  begin
    Result := '{' + string.Join(', ', mParts) + '}';
  end;
end;

function TStripper.RebuildArray(ANode: TJsonNode; const APath: string; out AChanged: Boolean): string;
var
  mIndex: Integer;
  mChild: string;
  mParts: TArray<string>;
begin
  AChanged := False;
  mParts := nil;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    if RebuildItem(ANode[mIndex], APath + '[]', AChanged, mChild) then
    begin
      mParts := mParts + [mChild];
    end;
  end;
  Result := NodeText(ANode);
  if AChanged then
  begin
    Result := '[' + string.Join(', ', mParts) + ']';
  end;
end;

function TStripper.Rebuild(ANode: TJsonNode; const APath: string; out AChanged: Boolean): string;
begin
  AChanged := False;
  if ANode.Kind = TJsonKind.Object_ then
  begin
    Exit(RebuildObject(ANode, APath, AChanged));
  end;
  if ANode.Kind = TJsonKind.Array_ then
  begin
    Exit(RebuildArray(ANode, APath, AChanged));
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
  begin
    Exit;
  end;
  try
    Root := TJsonTree.Parse(FText);
  except
    // Syntaxfehler meldet der Parser.
    on EJsonTreeError do
      Exit;
  end;
  try
    if Root.Kind <> TJsonKind.Object_ then
    begin
      Exit;
    end;
    Result := Rebuild(Root, '', Changed);
    if not Changed then
    begin
      Result := FText;
    end;
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
  begin
    if Item = APath then
    begin
      Exit(True);
    end;
  end;
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
