unit Atlas.Common.Lsp.SlashMenu;

// Erzeugen-Menü (#719) für workspace/executeCommand. Die Logik liegt in
// Atlas.Common.Editing.SlashMenu; Position und Markierung kommen vom Plugin,
// der Text aus dem Dokumentspeicher.
//   atlas.server.slashMenu [uri, position, endLine]: Orte an der Stelle und die
//     dort passenden Schnellbefehle, je mit Kurzbeschreibung, Beispiel,
//     Gruppe (generate/surround), Art des Arguments und ob es eine Auswahl
//     gibt. endLine ist die letzte Zeile der Markierung, -1 ohne.
//     Ergebnis: {"enabled", "places": [...], "commands": [...]}; "enabled" ist
//     false, wenn "slashCommands" für die Datei aus ist.
//   atlas.server.slashChoices [uri, position, endLine, name]: mögliche Argumente
//     (Felder für /ctor, Methoden für /override …) als Liste von Strings.
//   atlas.server.slashRun [uri, position, endLine, name, arguments]: führt den
//     Befehl aus, ohne dass im Editor etwas getippt wird. Ergebnis:
//     {"edits": [{range, newText}], "reason"}; reason ist leer, wenn es geklappt hat.
// Dazu kommt der Menübefehl "implement" ohne Schnellbefehl: „Interface
// implementieren“ wie in der Vervollständigung (#466) an einer gedachten leeren
// Zeile der Klasse. Er erscheint nach /override, wenn der Klasse Methoden ihrer
// Interfaces fehlen; die Auswahl sind diese Methoden als "IFoo.Bar", leer = alle.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.SlashMenu,
  Atlas.Common.Lsp.Completion;

type
  /// <summary>Delphi-Version (BDS-Nummer) je Dokument; '' = unbekannt.</summary>
  TSlashMenuVersionFunc = reference to function(const AUri: string): string;
  /// <summary>Formatstil je Dokument (#43: .editorconfig und "format").</summary>
  TSlashMenuStyleFunc = reference to function(const AUri: string): TFormatStyle;

  TLspSlashMenu = class
  public const
    MenuCommand = 'atlas.server.slashMenu';
    ChoicesCommand = 'atlas.server.slashChoices';
    RunCommand = 'atlas.server.slashRun';
    /// <summary>Menübefehl „Interface implementieren“ (#466) ohne Schnellbefehl.</summary>
    ImplementName = 'implement';
  private
    FStore: IDocumentStore;
    FSlashCommandsFor: TSlashCommandsProvider;
    FDelphiVersionFor: TSlashMenuVersionFunc;
    FFormatStyleFor: TSlashMenuStyleFunc;
    FIndex: ISymbolIndex;
    FSlashHost: ISlashHost;
    FCompletion: TLspCompletion;
    function Enabled(const AUri: string; out ADisabled: TArray<string>): Boolean;
    /// <summary>Fehlende Interface-Methoden der Klasse an ASpot als Einträge der Vervollständigung (Batch, #466);
    /// ihre Änderungen beziehen sich auf den Text mit der gedachten leeren Zeile ACommandLine.</summary>
    function MissingInterfaceMethods(const AUri, AText: string; const ASpot: TSlashSpot;
      out AItems: TArray<TCompletionItem>; out ACommandLine: Integer): Boolean;
    function RunImplement(const AUri, AText: string; const ASpot: TSlashSpot; const AArguments: string;
      out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
  public
    constructor Create(const AStore: IDocumentStore);
    function ExecuteMenu(const AArguments: TJSONArray): TJSONValue;
    function ExecuteChoices(const AArguments: TJSONArray): TJSONValue;
    function ExecuteRun(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Ohne Zuweisung sind alle Schnellbefehle eingeschaltet.</summary>
    property SlashCommandsFor: TSlashCommandsProvider read FSlashCommandsFor write FSlashCommandsFor;
    property DelphiVersionFor: TSlashMenuVersionFunc read FDelphiVersionFor write FDelphiVersionFor;
    /// <summary>Einrückung der Befehle (#43); ohne Zuweisung zwei Leerzeichen je Ebene.</summary>
    property FormatStyleFor: TSlashMenuStyleFunc read FFormatStyleFor write FFormatStyleFor;
    /// <summary>Index für Vorfahren aus anderen Units (/override, /ctor owner); nil ohne.</summary>
    property Index: ISymbolIndex read FIndex write FIndex;
    /// <summary>Projekt und Editor für Befehle wie /define; nil ohne.</summary>
    property SlashHost: ISlashHost read FSlashHost write FSlashHost;
    /// <summary>Für „Interface implementieren“: Namespaces, Dateien lesen und Abschnitt (completion.interfaceSection)
    /// wie in der Vervollständigung; nil ohne den Befehl. Gehört dem Aufrufer.</summary>
    property Completion: TLspCompletion read FCompletion write FCompletion;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Editing.InterfaceStubs;

/// <summary>Dokument zur URI und Stelle samt Markierung aus den ersten drei Argumenten.</summary>
function ReadSpot(const AStore: IDocumentStore; const AArguments: TJSONArray; ACount: Integer; out AUri: string;
  out ASpot: TSlashSpot): ITextDocument;
var
  Position: TTextPosition;
  EndLine: Integer;
begin
  if (AArguments = nil) or (AArguments.Count < ACount) or not (AArguments.Items[0] is TJSONString) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Erwartet werden URI, Position und letzte Zeile ' +
      'der Markierung');
  AUri := AArguments.Items[0].Value;
  if not AStore.TryGet(AUri, Result) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Dokument ist nicht geöffnet');
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  EndLine := -1;
  if AArguments.Items[2] is TJSONNumber then
    EndLine := TJSONNumber(AArguments.Items[2]).AsInt;
  ASpot := TSlashSpot.Create(Position.Line, Position.Character, EndLine);
end;

function StringAt(const AArguments: TJSONArray; AIndex: Integer): string;
begin
  Result := '';
  if (AArguments.Count > AIndex) and (AArguments.Items[AIndex] is TJSONString) then
    Result := AArguments.Items[AIndex].Value;
end;

function Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  Item: string;
begin
  Result := False;
  for Item in AList do
    if SameText(Trim(Item), Trim(AName)) then
      Exit(True);
end;

function NamesToJson(const ANames: TArray<string>): TJSONArray;
var
  Name: string;
begin
  Result := TJSONArray.Create;
  for Name in ANames do
    Result.Add(Name);
end;

{ TLspSlashMenu }

constructor TLspSlashMenu.Create(const AStore: IDocumentStore);
begin
  inherited Create;
  FStore := AStore;
end;

function TLspSlashMenu.Enabled(const AUri: string; out ADisabled: TArray<string>): Boolean;
begin
  ADisabled := nil;
  Result := True;
  if Assigned(FSlashCommandsFor) then
    Result := FSlashCommandsFor(AUri, ADisabled);
end;

function TLspSlashMenu.MissingInterfaceMethods(const AUri, AText: string; const ASpot: TSlashSpot;
  out AItems: TArray<TCompletionItem>; out ACommandLine: Integer): Boolean;
var
  Virtual, Line: string;
  WrapUntil: Integer;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Settings: TCompletionSettings;
  Batch: Boolean;
begin
  AItems := nil;
  ACommandLine := -1;
  Result := False;
  if (FCompletion = nil) or (FIndex = nil) or ASpot.HasSelection then
    Exit;
  // Gedachte leere Zeile wie für einen Schnellbefehl; dort bietet die Vervollständigung alle fehlenden Methoden an.
  if not TSlashMenu.Prepare(AText, TSlashSpot.Create(ASpot.Line, ASpot.Character, -1), '', Virtual, ACommandLine,
    WrapUntil) then
    Exit;
  Line := TTextLines.SplitLines(Virtual)[ACommandLine];
  Settings := TCompletionSettings.Default;
  if Assigned(FCompletion.SettingsFor) then
    Settings := FCompletion.SettingsFor(AUri);
  // Über den Cache: TSyntaxTreeCacheTests.NoParserCallsOutsideCache.
  Tree := TSyntaxTreeCache.Parse(Virtual);
  try
    Resolver := TNameResolver.Create(FIndex);
    try
      Resolver.Namespaces := FCompletion.Namespaces;
      Result := TLspCompletion.InterfaceItems(Resolver, Tree, Virtual, TDocumentUris.ToPath(AUri),
        TTextPosition.Create(ACommandLine, Length(Line)), FCompletion.ReadText,
        Settings.InterfaceSection, AItems, Batch) and Batch;
    finally
      Resolver.Free;
    end;
  finally
    Tree.Free;
  end;
  if not Result then
    AItems := nil;
end;

function TLspSlashMenu.RunImplement(const AUri, AText: string; const ASpot: TSlashSpot; const AArguments: string;
  out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Items: TArray<TCompletionItem>;
  Item: TCompletionItem;
  CommandLine: Integer;
  Chosen: TArray<string>;
  Edits: TArray<TRuleEdit>;
  LineBreak: string;
begin
  AEdits := nil;
  AReason := '';
  if not MissingInterfaceMethods(AUri, AText, ASpot, Items, CommandLine) then
  begin
    AReason := 'Hier fehlen keine Methoden eines Interfaces';
    Exit(False);
  end;
  Chosen := AArguments.Split([',', ';'], TStringSplitOptions.ExcludeEmpty);
  Edits := nil;
  for Item in Items do
    if (Length(Chosen) = 0) or Contains(Chosen, Item.Container + '.' + Item.Name) or Contains(Chosen, Item.Name) then
      Edits := Edits + Item.AdditionalEdits;
  if Length(Edits) = 0 then
  begin
    AReason := 'Keine der gewählten Methoden fehlt: ' + AArguments;
    Exit(False);
  end;
  LineBreak := TTextLines.LineBreakOf(AText);
  AEdits := TSlashMenu.MapEdits(TInterfaceStubs.Merge(Edits), CommandLine, '', LineBreak);
  Result := True;
end;

function TLspSlashMenu.ExecuteMenu(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Spot: TSlashSpot;
  Document: ITextDocument;
  Disabled: TArray<string>;
  IsEnabled: Boolean;
  Places: TSlashPlaces;
  Entry: TSlashMenuEntry;
  Command: TSlashCommand;
  Commands: TJSONArray;
  Item: TJSONObject;
  Missing: TArray<TCompletionItem>;
  CommandLine: Integer;

  procedure AddImplement;
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', ImplementName);
    Item.AddPair('summary', 'Fehlende Methoden der Interfaces anlegen');
    Item.AddPair('example', '');
    Item.AddPair('group', TSlashMenu.GroupName(TSlashGroup.Generate));
    Item.AddPair('argument', TSlashMenu.ArgumentName(TSlashArgument.Optional));
    Item.AddPair('choices', TJSONBool.Create(True));
    Item.AddPair('multi', TJSONBool.Create(True));
    Item.AddPair('separator', ', ');
    Commands.AddElement(Item);
  end;

begin
  Document := ReadSpot(FStore, AArguments, 3, Uri, Spot);
  IsEnabled := Enabled(Uri, Disabled);
  Places := TSlashMenu.PlacesAt(Document.Text, Spot);
  Result := TJSONObject.Create;
  try
    TJSONObject(Result).AddPair('enabled', TJSONBool.Create(IsEnabled));
    TJSONObject(Result).AddPair('places', NamesToJson(TSlashMenu.PlaceNames(Places)));
    Commands := TJSONArray.Create;
    TJSONObject(Result).AddPair('commands', Commands);
    if not IsEnabled then
      Exit;
    for Entry in TSlashMenu.Catalog do
    begin
      if Contains(Disabled, Entry.Name) or not TSlashMenu.Fits(Entry, Places, Spot.HasSelection) or
        not TSlashCommandRegistry.Shared.Find(Entry.Name, Command) then
        Continue;
      Item := TJSONObject.Create;
      Item.AddPair('name', Entry.Name);
      Item.AddPair('summary', Command.Summary);
      Item.AddPair('example', Command.Example);
      Item.AddPair('group', TSlashMenu.GroupName(Entry.Group));
      Item.AddPair('argument', TSlashMenu.ArgumentName(Entry.Argument));
      Item.AddPair('choices', TJSONBool.Create(Entry.HasChoices));
      Item.AddPair('multi', TJSONBool.Create(Entry.Multi));
      Item.AddPair('separator', Entry.Separator);
      Commands.AddElement(Item);
      // „Interface implementieren“ (#466) nach /override, wie im Mockup.
      if SameText(Entry.Name, 'override') and MissingInterfaceMethods(Uri, Document.Text, Spot, Missing,
        CommandLine) then
        AddImplement;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TLspSlashMenu.ExecuteChoices(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Spot: TSlashSpot;
  Document: ITextDocument;
  Missing: TArray<TCompletionItem>;
  Item: TCompletionItem;
  CommandLine: Integer;
  Names: TArray<string>;
begin
  Document := ReadSpot(FStore, AArguments, 4, Uri, Spot);
  if SameText(StringAt(AArguments, 3), ImplementName) then
  begin
    Names := nil;
    if MissingInterfaceMethods(Uri, Document.Text, Spot, Missing, CommandLine) then
      for Item in Missing do
        Names := Names + [Item.Container + '.' + Item.Name];
    Exit(NamesToJson(Names));
  end;
  Result := NamesToJson(TSlashMenu.Choices(Document.Text, Spot, StringAt(AArguments, 3), FIndex));
end;

function TLspSlashMenu.ExecuteRun(const AArguments: TJSONArray): TJSONValue;
var
  Uri, Version, Reason: string;
  Style: TFormatStyle;
  Spot: TSlashSpot;
  Document: ITextDocument;
  Disabled: TArray<string>;
  Edits: TArray<TRuleEdit>;
  Edit: TRuleEdit;
  List: TJSONArray;
  Item: TJSONObject;
begin
  Document := ReadSpot(FStore, AArguments, 4, Uri, Spot);
  Edits := nil;
  if not Enabled(Uri, Disabled) then
    Reason := 'Schnellbefehle sind für diese Datei abgeschaltet (slashCommands)'
  else
  begin
    Version := '';
    if Assigned(FDelphiVersionFor) then
      Version := FDelphiVersionFor(Uri);
    Style := TFormatStyle.Default;
    if Assigned(FFormatStyleFor) then
      Style := FFormatStyleFor(Uri);
    if SameText(StringAt(AArguments, 3), ImplementName) then
      RunImplement(Uri, Document.Text, Spot, StringAt(AArguments, 4), Edits, Reason)
    else
      TSlashMenu.Run(TSlashCommandRegistry.Shared, Document.Text, Spot, StringAt(AArguments, 3),
        StringAt(AArguments, 4), Disabled, FIndex, Version, Uri, FSlashHost, Style, Edits, Reason);
  end;
  Result := TJSONObject.Create;
  try
    List := TJSONArray.Create;
    TJSONObject(Result).AddPair('edits', List);
    for Edit in Edits do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
      Item.AddPair('newText', Edit.NewText);
      List.AddElement(Item);
    end;
    TJSONObject(Result).AddPair('reason', Reason);
  except
    Result.Free;
    raise;
  end;
end;

end.
