unit Atlas.Core.Generate.Protocol;

// Erzeugen-Menü (#719): Austausch mit dem Server und Einträge aus Code-
// Vorlagen und Code-Aktionen, ohne VCL und Open Tools API.
// Befehle des Servers (Atlas.Common.Lsp.SlashMenu) über workspace/executeCommand:
//   atlas.server.slashMenu [uri, position, endLine]: Orte und passende Schnellbefehle,
//   atlas.server.slashChoices [uri, position, endLine, name]: mögliche Argumente,
//   atlas.server.slashRun [uri, position, endLine, name, arguments]: Änderungen oder Grund.
// endLine ist die letzte Zeile der Markierung, -1 ohne.
// Vorlagen kommen in die Gruppe Vorlagen, wenn ihr Kontext (context: …) zu den
// Orten passt; in Kommentaren und Strings (keine Orte) gibt es keine. Code-
// Aktionen der Art refactor (ohne gesperrte) kommen in die Gruppe Erzeugen.

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Generate.Menu;

type
  /// <summary>Stelle im Editor: Datei, Cursor (ab 0) und letzte Zeile der Markierung (-1 ohne).</summary>
  TAtlasGenerateSpot = record
    Uri: string;
    Line: Integer;
    Character: Integer;
    EndLine: Integer;
    class function Create(const AUri: string; ALine, ACharacter, AEndLine: Integer): TAtlasGenerateSpot; static;
    function HasSelection: Boolean;
  end;

  /// <summary>Antwort auf atlas.server.slashMenu.</summary>
  TAtlasGenerateServerMenu = record
    /// <summary>False, wenn Schnellbefehle für die Datei aus sind (slashCommands).</summary>
    Enabled: Boolean;
    /// <summary>routine, class, record, interfaceType, interface, implementation, program; leer im Kommentar.</summary>
    Places: TArray<string>;
    Entries: TArray<TAtlasGenerateEntry>;
  end;

  TAtlasGenerateProtocol = class
  public const
    MenuCommand = 'atlas.server.slashMenu';
    ChoicesCommand = 'atlas.server.slashChoices';
    RunCommand = 'atlas.server.slashRun';
  public
    /// <summary>Argumente als JSON-Array-Text.</summary>
    class function MenuArguments(const ASpot: TAtlasGenerateSpot): string; static;
    class function ChoicesArguments(const ASpot: TAtlasGenerateSpot; const AName: string): string; static;
    class function RunArguments(const ASpot: TAtlasGenerateSpot; const AName, AArgument: string): string; static;
    /// <summary>Einträge der Gruppen Erzeugen und Umschließen mit der Kurzbeschreibung des Servers als
    /// Beschriftung (das Plugin setzt eigene Texte darüber). Unbekannte Felder werden übergangen.</summary>
    class function ParseMenu(const AValue: TJSONValue): TAtlasGenerateServerMenu; static;
    class function ParseChoices(const AValue: TJSONValue): TArray<string>; static;
    /// <summary>True mit AEdits, sonst False mit AReason.</summary>
    class function ParseRun(const AValue: TJSONValue; out AEdits: TArray<TLspTextEdit>;
      out AReason: string): Boolean; static;
    /// <summary>Vorlagen ohne Postfix- und Dateivorlagen (#759), deren Kontext zu APlaces passt; Source = Index
    /// in ASnippets.</summary>
    class function FromSnippets(const ASnippets: TAtlasSnippetList; const APlaces: TArray<string>):
      TArray<TAtlasGenerateEntry>; static;
    /// <summary>Code-Aktionen der Art refactor, nicht gesperrt; Source = Index in AActions.</summary>
    class function FromActions(const AActions: TArray<TLspCodeAction>): TArray<TAtlasGenerateEntry>; static;
  end;

implementation


uses
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TProtocolText = (NoAnswerFromTheServer, TheCommandChangedNothing);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TProtocolText] of string = (
    ('Keine Antwort des Servers',
     'Der Befehl hat nichts geändert'),
    ('No answer from the server',
     'The command changed nothing'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TProtocolText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;
{ TAtlasGenerateSpot }

class function TAtlasGenerateSpot.Create(const AUri: string; ALine, ACharacter,
  AEndLine: Integer): TAtlasGenerateSpot;
begin
  Result.Uri := AUri;
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.EndLine := AEndLine;
end;

function TAtlasGenerateSpot.HasSelection: Boolean;
begin
  Result := EndLine >= 0;
end;

{ TAtlasGenerateProtocol }

function SpotArray(const ASpot: TAtlasGenerateSpot): TJSONArray;
var
  mPosition: TJSONObject;
begin
  mPosition := TJSONObject.Create;
  mPosition.AddPair('line', TJSONNumber.Create(ASpot.Line));
  mPosition.AddPair('character', TJSONNumber.Create(ASpot.Character));
  Result := TJSONArray.Create;
  Result.Add(ASpot.Uri);
  Result.AddElement(mPosition);
  Result.Add(ASpot.EndLine);
end;

function ArrayText(AArray: TJSONArray): string;
begin
  try
    Result := AArray.ToJSON;
  finally
    AArray.Free;
  end;
end;

class function TAtlasGenerateProtocol.MenuArguments(const ASpot: TAtlasGenerateSpot): string;
begin
  Result := ArrayText(SpotArray(ASpot));
end;

class function TAtlasGenerateProtocol.ChoicesArguments(const ASpot: TAtlasGenerateSpot; const AName: string): string;
var
  mValues: TJSONArray;
begin
  mValues := SpotArray(ASpot);
  mValues.Add(AName);
  Result := ArrayText(mValues);
end;

class function TAtlasGenerateProtocol.RunArguments(const ASpot: TAtlasGenerateSpot; const AName,
  AArgument: string): string;
var
  mValues: TJSONArray;
begin
  mValues := SpotArray(ASpot);
  mValues.Add(AName);
  mValues.Add(AArgument);
  Result := ArrayText(mValues);
end;

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
  end;
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AObject.GetValue(AName);
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

function PlacesOf(const AValue: TJSONValue): TArray<string>;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(AValue) do
  begin
    if mValue is TJSONString then
    begin
      Result := Result + [TJSONString(mValue).Value];
    end;
  end;
end;

/// <summary>Gruppe eines Serverbefehls; „Zuletzt“, „Vorlagen“ und Unbekanntes landen unter „Erzeugen“.</summary>
function ServerGroupOf(const AText: string): TAtlasGenerateGroup;
begin
  if not TAtlasGenerateOptions.TryParseGroup(AText, Result) or (Result = TAtlasGenerateGroup.Recent) or
    (Result = TAtlasGenerateGroup.Templates) then
  begin
    Result := TAtlasGenerateGroup.Generate;
  end;
end;

function ArgumentOf(const AText: string): TAtlasGenerateArgument;
begin
  if SameText(AText, 'required') then
  begin
    Result := TAtlasGenerateArgument.Required;
  end
  else if SameText(AText, 'optional') then
  begin
    Result := TAtlasGenerateArgument.Optional;
  end
  else
  begin
    Result := TAtlasGenerateArgument.None;
  end;
end;

/// <summary>Eintrag aus einem Element von „commands“; False ohne Objekt oder Namen.</summary>
function TryMenuEntry(const AValue: TJSONValue; out AEntry: TAtlasGenerateEntry): Boolean;
var
  mItem: TJSONObject;
begin
  Result := (AValue is TJSONObject) and (StringOf(TJSONObject(AValue), 'name') <> '');
  if not Result then
  begin
    Exit;
  end;
  mItem := TJSONObject(AValue);
  AEntry := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Slash, ServerGroupOf(StringOf(mItem, 'group')),
    StringOf(mItem, 'name'), StringOf(mItem, 'summary'));
  AEntry.Detail := StringOf(mItem, 'summary');
  AEntry.Example := StringOf(mItem, 'example');
  AEntry.Argument := ArgumentOf(StringOf(mItem, 'argument'));
  AEntry.HasChoices := FlagOf(mItem, 'choices');
  AEntry.Multi := FlagOf(mItem, 'multi');
  AEntry.Separator := StringOf(mItem, 'separator');
  if AEntry.Separator = '' then
  begin
    AEntry.Separator := ' ';
  end;
end;
class function TAtlasGenerateProtocol.ParseMenu(const AValue: TJSONValue): TAtlasGenerateServerMenu;
var
  mRoot: TJSONObject;
  mValue: TJSONValue;
  mEntry: TAtlasGenerateEntry;
begin
  Result := Default(TAtlasGenerateServerMenu);
  Result.Places := nil;
  Result.Entries := nil;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mRoot := TJSONObject(AValue);
  Result.Enabled := FlagOf(mRoot, 'enabled');
  Result.Places := PlacesOf(mRoot.GetValue('places'));
  if mRoot.GetValue('commands') is TJSONArray then
  begin
    for mValue in TJSONArray(mRoot.GetValue('commands')) do
    begin
      if TryMenuEntry(mValue, mEntry) then
      begin
        Result.Entries := Result.Entries + [mEntry];
      end;
    end;
  end;
end;

class function TAtlasGenerateProtocol.ParseChoices(const AValue: TJSONValue): TArray<string>;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mValue in TJSONArray(AValue) do
    begin
      if mValue is TJSONString then
      begin
        Result := Result + [TJSONString(mValue).Value];
      end;
    end;
  end;
end;

class function TAtlasGenerateProtocol.ParseRun(const AValue: TJSONValue; out AEdits: TArray<TLspTextEdit>;
  out AReason: string): Boolean;
var
  mRoot: TJSONObject;
  mValue: TJSONValue;
  mEdit: TLspTextEdit;
begin
  AEdits := nil;
  AReason := '';
  Result := False;
  if not (AValue is TJSONObject) then
  begin
    AReason := UiText(TProtocolText.NoAnswerFromTheServer);
    Exit;
  end;
  mRoot := TJSONObject(AValue);
  AReason := StringOf(mRoot, 'reason');
  if mRoot.GetValue('edits') is TJSONArray then
  begin
    for mValue in TJSONArray(mRoot.GetValue('edits')) do
    begin
      if TLspTextEdit.FromJson(mValue, mEdit) then
      begin
        AEdits := AEdits + [mEdit];
      end;
    end;
  end;
  Result := (AReason = '') and (Length(AEdits) > 0);
  if not Result and (AReason = '') then
  begin
    AReason := UiText(TProtocolText.TheCommandChangedNothing);
  end;
end;

class function TAtlasGenerateProtocol.FromSnippets(const ASnippets: TAtlasSnippetList;
  const APlaces: TArray<string>): TArray<TAtlasGenerateEntry>;
var
  mIndex: Integer;
  mEntry: TAtlasGenerateEntry;
begin
  Result := nil;
  // Kein Ort: Kommentar, String oder asm; dort passt keine Vorlage.
  if Length(APlaces) = 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ASnippets) do
  begin
    // Dateivorlagen (#759) gehören zu „Neu mit Atlas“, nicht an den Cursor.
    if ASnippets[mIndex].Postfix or (ASnippets[mIndex].FileKind <> '') or
      not TAtlasSnippets.FitsContext(ASnippets[mIndex].Context, APlaces) then
    begin
      Continue;
    end;
    mEntry := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Snippet, TAtlasGenerateGroup.Templates,
      ASnippets[mIndex].Prefix, ASnippets[mIndex].Name);
    if mEntry.Caption = '' then
    begin
      mEntry.Caption := ASnippets[mIndex].Prefix;
    end;
    mEntry.Detail := ASnippets[mIndex].Description;
    mEntry.Source := mIndex;
    Result := Result + [mEntry];
  end;
end;

class function TAtlasGenerateProtocol.FromActions(const AActions: TArray<TLspCodeAction>):
  TArray<TAtlasGenerateEntry>;
var
  mIndex: Integer;
  mEntry: TAtlasGenerateEntry;
begin
  Result := nil;
  for mIndex := 0 to High(AActions) do
  begin
    if (AActions[mIndex].Disabled <> '') or not AActions[mIndex].Kind.StartsWith('refactor') then
    begin
      Continue;
    end;
    mEntry := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Action, TAtlasGenerateGroup.Generate,
      AActions[mIndex].Title, AActions[mIndex].Title);
    mEntry.Source := mIndex;
    Result := Result + [mEntry];
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Generate.Protocol', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
