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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.SlashMenu,
  Atlas.Common.Lsp.Completion;

type
  /// <summary>Delphi-Version (BDS-Nummer) je Dokument; '' = unbekannt.</summary>
  TSlashMenuVersionFunc = reference to function(const AUri: string): string;
  /// <summary>Formatstil je Dokument (#43: .editorconfig und "format").</summary>
  TSlashMenuStyleFunc = reference to function(const AUri: string): TFormatStyle;

  TLspSlashMenu = class
  public const
    cMenuCommand = 'atlas.server.slashMenu';
    cChoicesCommand = 'atlas.server.slashChoices';
    cRunCommand = 'atlas.server.slashRun';
    /// <summary>Menübefehl „Interface implementieren“ (#466) ohne Schnellbefehl.</summary>
    cImplementName = 'implement';
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
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion.Declarations,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspSlashMenuText = (URIPositionAndLastLine, DocumentIsNotOpen, NoMethodsOfAnInterface, NoneOfTheChosenMethods,
    CreateMissingMethodsOfThe, SlashCommandsAreSwitchedOff);

const
  cTexts: array[TLspSlashMenuText] of TAtlasText = (
    (De: 'Erwartet werden URI, Position und letzte Zeile der Markierung';
     En: 'URI, position and last line of the selection expected'),
    (De: 'Dokument ist nicht geöffnet'; En: 'Document is not open'),
    (De: 'Hier fehlen keine Methoden eines Interfaces'; En: 'No methods of an interface are missing here'),
    (De: 'Keine der gewählten Methoden fehlt: '; En: 'None of the chosen methods is missing: '),
    (De: 'Fehlende Methoden der Interfaces anlegen'; En: 'Create missing methods of the interfaces'),
    (De: 'Schnellbefehle sind für diese Datei abgeschaltet (slashCommands)';
     En: 'Slash commands are switched off for this file (slashCommands)'));

{$SCOPEDENUMS OFF}

/// <summary>Dokument zur URI und Stelle samt Markierung aus den ersten drei Argumenten.</summary>
function ReadSpot(const AStore: IDocumentStore; const AArguments: TJSONArray; ACount: Integer; out AUri: string;
  out ASpot: TSlashSpot): ITextDocument;
var
  mPosition: TTextPosition;
  mEndLine: Integer;
begin
  if (AArguments = nil) or (AArguments.Count < ACount) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TLspSlashMenuText.URIPositionAndLastLine].Text);
  end;
  AUri := AArguments.Items[0].Value;
  if not AStore.TryGet(AUri, Result) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TLspSlashMenuText.DocumentIsNotOpen].Text);
  end;
  mPosition := TLspPositions.ReadPosition(AArguments.Items[1]);
  mEndLine := -1;
  if AArguments.Items[2] is TJSONNumber then
  begin
    mEndLine := TJSONNumber(AArguments.Items[2]).AsInt;
  end;
  ASpot := TSlashSpot.Create(mPosition.Line, mPosition.Character, mEndLine);
end;

function StringAt(const AArguments: TJSONArray; AIndex: Integer): string;
begin
  Result := '';
  if (AArguments.Count > AIndex) and (AArguments.Items[AIndex] is TJSONString) then
  begin
    Result := AArguments.Items[AIndex].Value;
  end;
end;

function Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  mItem: string;
begin
  Result := False;
  for mItem in AList do
  begin
    if SameText(Trim(mItem), Trim(AName)) then
    begin
      Exit(True);
    end;
  end;
end;

function NamesToJson(const ANames: TArray<string>): TJSONArray;
var
  mName: string;
begin
  Result := TJSONArray.Create;
  for mName in ANames do
  begin
    Result.Add(mName);
  end;
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
  begin
    Result := FSlashCommandsFor(AUri, ADisabled);
  end;
end;

function TLspSlashMenu.MissingInterfaceMethods(const AUri, AText: string; const ASpot: TSlashSpot;
  out AItems: TArray<TCompletionItem>; out ACommandLine: Integer): Boolean;
var
  mVirtual, mLine: string;
  mWrapUntil: Integer;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mSettings: TCompletionSettings;
  mBatch: Boolean;
  mRequest: TCompletionRequest;
begin
  AItems := nil;
  ACommandLine := -1;
  Result := False;
  if (FCompletion = nil) or (FIndex = nil) or ASpot.HasSelection then
  begin
    Exit;
  end;
  // Gedachte leere Zeile wie für einen Schnellbefehl; dort bietet die Vervollständigung alle fehlenden Methoden an.
  if not TSlashMenu.Prepare(AText, TSlashSpot.Create(ASpot.Line, ASpot.Character, -1), '', mVirtual, ACommandLine,
    mWrapUntil) then
  begin
    Exit;
  end;
  mLine := TTextLines.SplitLines(mVirtual)[ACommandLine];
  mSettings := TCompletionSettings.Default;
  if Assigned(FCompletion.Hooks.SettingsFor) then
  begin
    mSettings := FCompletion.Hooks.SettingsFor(AUri);
  end;
  // Über den Cache: TSyntaxTreeCacheTests.NoParserCallsOutsideCache.
  mTree := TSyntaxTreeCache.Parse(mVirtual);
  mResolver := nil;
  mRequest := nil;
  try
    mResolver := TNameResolver.Create(FIndex);
    mResolver.Namespaces := FCompletion.Hooks.Namespaces;
    mRequest := TCompletionRequest.Create(mVirtual, TDocumentUris.ToPath(AUri),
      TTextPosition.Create(ACommandLine, Length(mLine)));
    mRequest.Tree := mTree;
    mRequest.Resolver := mResolver;
    mRequest.ReadText := FCompletion.Hooks.ReadText;
    mRequest.Settings := mSettings;
    Result := TCompletionDeclarations.InterfaceItems(mRequest, AItems, mBatch) and mBatch;
  finally
    mRequest.Free;
    mResolver.Free;
    mTree.Free;
  end;
  if not Result then
  begin
    AItems := nil;
  end;
end;

function TLspSlashMenu.RunImplement(const AUri, AText: string; const ASpot: TSlashSpot; const AArguments: string;
  out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  mItems: TArray<TCompletionItem>;
  mItem: TCompletionItem;
  mCommandLine: Integer;
  mChosen: TArray<string>;
  mEdits: TArray<TRuleEdit>;
  mLineBreak: string;
begin
  AEdits := nil;
  AReason := '';
  if not MissingInterfaceMethods(AUri, AText, ASpot, mItems, mCommandLine) then
  begin
    AReason := cTexts[TLspSlashMenuText.NoMethodsOfAnInterface].Text;
    Exit(False);
  end;
  mChosen := AArguments.Split([',', ';'], TStringSplitOptions.ExcludeEmpty);
  mEdits := nil;
  for mItem in mItems do
  begin
    if (Length(mChosen) = 0) or Contains(mChosen, mItem.Container + '.' + mItem.Name) or
      Contains(mChosen, mItem.Name) then
    begin
      mEdits := mEdits + mItem.AdditionalEdits;
    end;
  end;
  if Length(mEdits) = 0 then
  begin
    AReason := cTexts[TLspSlashMenuText.NoneOfTheChosenMethods].Text + AArguments;
    Exit(False);
  end;
  mLineBreak := TTextLines.LineBreakOf(AText);
  AEdits := TSlashMenu.MapEdits(TInterfaceStubs.Merge(mEdits), mCommandLine, '', mLineBreak);
  Result := True;
end;

function TLspSlashMenu.ExecuteMenu(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mSpot: TSlashSpot;
  mDocument: ITextDocument;
  mDisabled: TArray<string>;
  mIsEnabled: Boolean;
  mPlaces: TSlashPlaces;
  mEntry: TSlashMenuEntry;
  mCommand: TSlashCommand;
  mCommands: TJSONArray;
  mItem: TJSONObject;
  mMissing: TArray<TCompletionItem>;
  mCommandLine: Integer;

  procedure AddImplement;
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', cImplementName);
    mItem.AddPair('summary', cTexts[TLspSlashMenuText.CreateMissingMethodsOfThe].Text);
    mItem.AddPair('example', '');
    mItem.AddPair('group', TSlashMenu.GroupName(TSlashGroup.Generate));
    mItem.AddPair('argument', TSlashMenu.ArgumentName(TSlashArgument.Optional));
    mItem.AddPair('choices', TJSONBool.Create(True));
    mItem.AddPair('multi', TJSONBool.Create(True));
    mItem.AddPair('separator', ', ');
    mCommands.AddElement(mItem);
  end;

begin
  mDocument := ReadSpot(FStore, AArguments, 3, mUri, mSpot);
  mIsEnabled := Enabled(mUri, mDisabled);
  mPlaces := TSlashMenu.PlacesAt(mDocument.Text, mSpot);
  Result := TJSONObject.Create;
  try
    TJSONObject(Result).AddPair('enabled', TJSONBool.Create(mIsEnabled));
    TJSONObject(Result).AddPair('places', NamesToJson(TSlashMenu.PlaceNames(mPlaces)));
    mCommands := TJSONArray.Create;
    TJSONObject(Result).AddPair('commands', mCommands);
    if not mIsEnabled then
    begin
      Exit;
    end;
    for mEntry in TSlashMenu.Catalog do
    begin
      if Contains(mDisabled, mEntry.Name) or not TSlashMenu.Fits(mEntry, mPlaces, mSpot.HasSelection) or
        not TSlashCommandRegistry.Shared.Find(mEntry.Name, mCommand) then
      begin
        Continue;
      end;
      mItem := TJSONObject.Create;
      mItem.AddPair('name', mEntry.Name);
      mItem.AddPair('summary', mCommand.Summary);
      mItem.AddPair('example', mCommand.Example);
      mItem.AddPair('group', TSlashMenu.GroupName(mEntry.Group));
      mItem.AddPair('argument', TSlashMenu.ArgumentName(mEntry.Argument));
      mItem.AddPair('choices', TJSONBool.Create(mEntry.HasChoices));
      mItem.AddPair('multi', TJSONBool.Create(mEntry.Multi));
      mItem.AddPair('separator', mEntry.Separator);
      mCommands.AddElement(mItem);
      // „Interface implementieren“ (#466) nach /override, wie im Mockup.
      if SameText(mEntry.Name, 'override') and MissingInterfaceMethods(mUri, mDocument.Text, mSpot, mMissing,
        mCommandLine) then
      begin
        AddImplement;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TLspSlashMenu.ExecuteChoices(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mSpot: TSlashSpot;
  mDocument: ITextDocument;
  mMissing: TArray<TCompletionItem>;
  mItem: TCompletionItem;
  mCommandLine: Integer;
  mNames: TArray<string>;
begin
  mDocument := ReadSpot(FStore, AArguments, 4, mUri, mSpot);
  if SameText(StringAt(AArguments, 3), cImplementName) then
  begin
    mNames := nil;
    if MissingInterfaceMethods(mUri, mDocument.Text, mSpot, mMissing, mCommandLine) then
    begin
      for mItem in mMissing do
      begin
        mNames := mNames + [mItem.Container + '.' + mItem.Name];
      end;
    end;
    Exit(NamesToJson(mNames));
  end;
  Result := NamesToJson(TSlashMenu.Choices(mDocument.Text, mSpot, StringAt(AArguments, 3), FIndex));
end;

function TLspSlashMenu.ExecuteRun(const AArguments: TJSONArray): TJSONValue;
var
  mUri, mVersion, mReason: string;
  mStyle: TFormatStyle;
  mSpot: TSlashSpot;
  mDocument: ITextDocument;
  mDisabled: TArray<string>;
  mEdits: TArray<TRuleEdit>;
  mEdit: TRuleEdit;
  mList: TJSONArray;
  mItem: TJSONObject;
begin
  mDocument := ReadSpot(FStore, AArguments, 4, mUri, mSpot);
  mEdits := nil;
  if not Enabled(mUri, mDisabled) then
  begin
    mReason := cTexts[TLspSlashMenuText.SlashCommandsAreSwitchedOff].Text;
  end
  else
  begin
    mVersion := '';
    if Assigned(FDelphiVersionFor) then
    begin
      mVersion := FDelphiVersionFor(mUri);
    end;
    mStyle := TFormatStyle.Default;
    if Assigned(FFormatStyleFor) then
    begin
      mStyle := FFormatStyleFor(mUri);
    end;
    if SameText(StringAt(AArguments, 3), cImplementName) then
    begin
      RunImplement(mUri, mDocument.Text, mSpot, StringAt(AArguments, 4), mEdits, mReason);
    end
    else
    begin
      TSlashMenu.Run(TSlashCommandRegistry.Shared, mDocument.Text, mSpot,
        TSlashMenuCall.Create(StringAt(AArguments, 3), StringAt(AArguments, 4),
        TSlashEnvironment.Create(nil, mDisabled, FIndex, mVersion, mUri, FSlashHost).WithStyle(mStyle)), mEdits,
          mReason);
    end;
  end;
  Result := TJSONObject.Create;
  try
    mList := TJSONArray.Create;
    TJSONObject(Result).AddPair('edits', mList);
    for mEdit in mEdits do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
      mItem.AddPair('newText', mEdit.NewText);
      mList.AddElement(mItem);
    end;
    TJSONObject(Result).AddPair('reason', mReason);
  except
    Result.Free;
    raise;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.SlashMenu', cTexts);

end.
