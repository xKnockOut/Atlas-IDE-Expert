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
  Position: TJSONObject;
begin
  Position := TJSONObject.Create;
  Position.AddPair('line', TJSONNumber.Create(ASpot.Line));
  Position.AddPair('character', TJSONNumber.Create(ASpot.Character));
  Result := TJSONArray.Create;
  Result.Add(ASpot.Uri);
  Result.AddElement(Position);
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
  Values: TJSONArray;
begin
  Values := SpotArray(ASpot);
  Values.Add(AName);
  Result := ArrayText(Values);
end;

class function TAtlasGenerateProtocol.RunArguments(const ASpot: TAtlasGenerateSpot; const AName,
  AArgument: string): string;
var
  Values: TJSONArray;
begin
  Values := SpotArray(ASpot);
  Values.Add(AName);
  Values.Add(AArgument);
  Result := ArrayText(Values);
end;

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

class function TAtlasGenerateProtocol.ParseMenu(const AValue: TJSONValue): TAtlasGenerateServerMenu;
var
  Root, Item: TJSONObject;
  Value: TJSONValue;
  Entry: TAtlasGenerateEntry;
  Group: TAtlasGenerateGroup;
  Argument: string;
begin
  Result := Default(TAtlasGenerateServerMenu);
  Result.Places := nil;
  Result.Entries := nil;
  if not (AValue is TJSONObject) then
    Exit;
  Root := TJSONObject(AValue);
  Result.Enabled := FlagOf(Root, 'enabled');
  if Root.GetValue('places') is TJSONArray then
    for Value in TJSONArray(Root.GetValue('places')) do
      if Value is TJSONString then
        Result.Places := Result.Places + [TJSONString(Value).Value];
  if not (Root.GetValue('commands') is TJSONArray) then
    Exit;
  for Value in TJSONArray(Root.GetValue('commands')) do
  begin
    if not (Value is TJSONObject) then
      Continue;
    Item := TJSONObject(Value);
    if StringOf(Item, 'name') = '' then
      Continue;
    if not TAtlasGenerateOptions.TryParseGroup(StringOf(Item, 'group'), Group) or
      (Group = TAtlasGenerateGroup.Recent) or (Group = TAtlasGenerateGroup.Templates) then
      Group := TAtlasGenerateGroup.Generate;
    Entry := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Slash, Group, StringOf(Item, 'name'),
      StringOf(Item, 'summary'));
    Entry.Detail := StringOf(Item, 'summary');
    Entry.Example := StringOf(Item, 'example');
    Argument := StringOf(Item, 'argument');
    if SameText(Argument, 'required') then
      Entry.Argument := TAtlasGenerateArgument.Required
    else if SameText(Argument, 'optional') then
      Entry.Argument := TAtlasGenerateArgument.Optional
    else
      Entry.Argument := TAtlasGenerateArgument.None;
    Entry.HasChoices := FlagOf(Item, 'choices');
    Entry.Multi := FlagOf(Item, 'multi');
    Entry.Separator := StringOf(Item, 'separator');
    if Entry.Separator = '' then
      Entry.Separator := ' ';
    Result.Entries := Result.Entries + [Entry];
  end;
end;

class function TAtlasGenerateProtocol.ParseChoices(const AValue: TJSONValue): TArray<string>;
var
  Value: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
    for Value in TJSONArray(AValue) do
      if Value is TJSONString then
        Result := Result + [TJSONString(Value).Value];
end;

class function TAtlasGenerateProtocol.ParseRun(const AValue: TJSONValue; out AEdits: TArray<TLspTextEdit>;
  out AReason: string): Boolean;
var
  Root: TJSONObject;
  Value: TJSONValue;
  Edit: TLspTextEdit;
begin
  AEdits := nil;
  AReason := '';
  Result := False;
  if not (AValue is TJSONObject) then
  begin
    AReason := 'Keine Antwort des Servers';
    Exit;
  end;
  Root := TJSONObject(AValue);
  AReason := StringOf(Root, 'reason');
  if Root.GetValue('edits') is TJSONArray then
    for Value in TJSONArray(Root.GetValue('edits')) do
      if TLspTextEdit.FromJson(Value, Edit) then
        AEdits := AEdits + [Edit];
  Result := (AReason = '') and (Length(AEdits) > 0);
  if not Result and (AReason = '') then
    AReason := 'Der Befehl hat nichts geändert';
end;

class function TAtlasGenerateProtocol.FromSnippets(const ASnippets: TAtlasSnippetList;
  const APlaces: TArray<string>): TArray<TAtlasGenerateEntry>;
var
  Index: Integer;
  Entry: TAtlasGenerateEntry;
begin
  Result := nil;
  // Kein Ort: Kommentar, String oder asm; dort passt keine Vorlage.
  if Length(APlaces) = 0 then
    Exit;
  for Index := 0 to High(ASnippets) do
  begin
    // Dateivorlagen (#759) gehören zu „Neu mit Atlas“, nicht an den Cursor.
    if ASnippets[Index].Postfix or (ASnippets[Index].FileKind <> '') or
      not TAtlasSnippets.FitsContext(ASnippets[Index].Context, APlaces) then
      Continue;
    Entry := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Snippet, TAtlasGenerateGroup.Templates,
      ASnippets[Index].Prefix, ASnippets[Index].Name);
    if Entry.Caption = '' then
      Entry.Caption := ASnippets[Index].Prefix;
    Entry.Detail := ASnippets[Index].Description;
    Entry.Source := Index;
    Result := Result + [Entry];
  end;
end;

class function TAtlasGenerateProtocol.FromActions(const AActions: TArray<TLspCodeAction>):
  TArray<TAtlasGenerateEntry>;
var
  Index: Integer;
  Entry: TAtlasGenerateEntry;
begin
  Result := nil;
  for Index := 0 to High(AActions) do
  begin
    if (AActions[Index].Disabled <> '') or not AActions[Index].Kind.StartsWith('refactor') then
      Continue;
    Entry := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Action, TAtlasGenerateGroup.Generate,
      AActions[Index].Title, AActions[Index].Title);
    Entry.Source := Index;
    Result := Result + [Entry];
  end;
end;

end.
