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
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TForbiddenText = (ContainsCredentialsInTheAddress, AbsolutePathsDoNotBelong, LooksLikeCredentialsTheyDo);

const
  cTexts: array[TForbiddenText] of TAtlasText = (
    (De: '"%s" enthält Zugangsdaten in der Adresse; atlas.json gilt für alle im Team, der Wert wird ignoriert';
     En: '"%s" contains credentials in the address; atlas.json applies to everyone in the team, the value is ignored'),
    (De: '"%s": absolute Pfade gehören nicht in atlas.json (gilt für alle im Team); der Wert wird ignoriert, bitte ' +
      'relativ zum Projektordner angeben';
     En: '"%s": absolute paths do not belong in atlas.json (applies to everyone in the team); the value is ignored, ' +
      'please give it relative to the project folder'),
    (De: '"%s" sieht nach Zugangsdaten aus; die gehören nicht in atlas.json (gilt für alle im Team, Anmeldespeicher ' +
      'von Windows verwenden) und werden ignoriert';
     En: '"%s" looks like credentials; they do not belong in atlas.json (applies to everyone in the team, use the ' +
      'Windows Credential Manager) and are ignored'));

{$SCOPEDENUMS OFF}

const
  cPathSettings: array[0..5] of string = ('project', 'testUnits.folder', 'testUnits.project', 'exclude[]',
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
  mCh: Char;
begin
  Result := '"';
  for mCh in AKey do
  begin
    if (mCh = '"') or (mCh = '\') then
    begin
      Result := Result + '\' + mCh;
    end
    else if Ord(mCh) < 32 then
    begin
      Result := Result + Format('\u%.4x', [Ord(mCh)]);
    end
    else
    begin
      Result := Result + mCh;
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
  mIssue: TConfigurationIssue;
begin
  mIssue.Range := TTextRange.Create(FLines.PositionAt(AStart), FLines.PositionAt(AStop));
  mIssue.Message := AMessage;
  mIssue.IsError := False;
  FIssues := FIssues + [mIssue];
end;

function TStripper.NodeText(ANode: TJsonNode): string;
begin
  Result := Copy(FText, ANode.Start + 1, ANode.Stop - ANode.Start);
end;

function TStripper.Forbidden(ANode: TJsonNode; const APath: string): Boolean;
var
  mShown: string;
begin
  Result := False;
  if ANode.Kind <> TJsonKind.String_ then
  begin
    Exit;
  end;
  mShown := StringReplace(APath, '[]', '', [rfReplaceAll]);
  if TTextCheckin.HasUrlCredentials(ANode.Value) then
  begin
    Report(ANode.Start, ANode.Stop, cTexts[TForbiddenText.ContainsCredentialsInTheAddress].Fmt([mShown]));
    Exit(True);
  end;
  if TForbiddenEntries.IsPathSetting(APath) and TTextCheckin.IsMachinePath(ANode.Value) then
  begin
    Report(ANode.Start, ANode.Stop, cTexts[TForbiddenText.AbsolutePathsDoNotBelong].Fmt([mShown]));
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
      Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        cTexts[TForbiddenText.LooksLikeCredentialsTheyDo].Fmt([mPath]));
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
  mRoot: TJsonNode;
  mChanged: Boolean;
begin
  Result := FText;
  if Trim(FText) = '' then
  begin
    Exit;
  end;
  try
    mRoot := TJsonTree.Parse(FText);
  except
    // Syntaxfehler meldet der Parser.
    on EJsonTreeError do
      Exit;
  end;
  try
    if mRoot.Kind <> TJsonKind.Object_ then
    begin
      Exit;
    end;
    Result := Rebuild(mRoot, '', mChanged);
    if not mChanged then
    begin
      Result := FText;
    end;
  finally
    mRoot.Free;
  end;
end;

{ TForbiddenEntries }

class function TForbiddenEntries.IsPathSetting(const APath: string): Boolean;
var
  mItem: string;
begin
  for mItem in cPathSettings do
  begin
    if mItem = APath then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TForbiddenEntries.Strip(const AText: string; out AIssues: TArray<TConfigurationIssue>): string;
var
  mStripper: TStripper;
begin
  mStripper := TStripper.Create(AText);
  try
    Result := mStripper.Run;
    AIssues := mStripper.Issues;
  finally
    mStripper.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Configuration.Internals.Forbidden', cTexts);

end.
