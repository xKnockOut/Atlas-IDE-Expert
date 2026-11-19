unit Atlas.Common.Mcp.RefactorTools;

// MCP-Werkzeug refactor (#2150): alle Umbauten einer Stelle auflisten und mit Argumenten ausführen.
// Die Umbauten kommen aus derselben Quelle wie im Editor (Code-Aktionen des Servers über TMcpRefactorSource).
// Aktionen mit Edits wendet das Werkzeug an, auf Wunsch nur mit einem Teil der abwählbaren Stellen (choices).
// Aktionen mit einem Befehl des Plugins (atlas.<Art>) führt es über den Befehl des Servers atlas.server.<Art> aus;
// was das Plugin dort per Dialog erfragt (Name, Ziel, Auswahl, Signatur), kommt aus args. Umbauten mit
// Vorbereitung (atlas.server.<Art>.prepare) holen daraus die Vorgaben der Anfrage, wie sie der Dialog vorbelegt.
// Geschrieben wird über TMcpEditTools.ApplyChanges wie bei apply_code_action, samt neuer und gelöschter Dateien;
// dryRun (Vorgabe) liefert nur den Diff. Hinweise des Umbaus (nicht geänderte Stellen) stehen unter dem Diff.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Mcp.EditTools;

type
  /// <summary>Code-Aktionen an ARange (ab 0) der geöffneten Datei AFileName als LSP-CodeAction-Liste. Der Aufrufer
  /// übernimmt das Array.</summary>
  TMcpRefactorActionsFunc = reference to function(const AFileName: string; const ARange: TTextRange): TJSONArray;
  /// <summary>Führt einen Befehl des Servers aus (workspace/executeCommand); der Aufrufer übernimmt das Ergebnis.
  /// Fehler des Befehls als EJsonRpcError.</summary>
  TMcpRefactorExecuteFunc = reference to function(const ACommand: string; const AArguments: TJSONArray): TJSONValue;

  /// <summary>Woher die Umbauten kommen: Code-Aktionen und Befehle des Servers für die geöffnete Datei.</summary>
  TMcpRefactorSource = record
    Actions: TMcpRefactorActionsFunc;
    Execute: TMcpRefactorExecuteFunc;
  end;

  /// <summary>Eingaben von refactor.</summary>
  TMcpRefactorRequest = record
    FileName: string;
    /// <summary>Stelle bzw. Auswahl, ab 0.</summary>
    Range: TTextRange;
    /// <summary>Schlüssel oder Titel des Umbaus; '' = auflisten.</summary>
    Kind: string;
    /// <summary>Wählt unter mehreren Umbauten mit demselben Schlüssel; '' = der einzige.</summary>
    Title: string;
    /// <summary>Argumente des Umbaus; nil = keine. Gehört dem Aufrufer.</summary>
    Args: TJSONObject;
    DryRun: Boolean;
    /// <summary>Liste bzw. Änderungen als JSON statt Markdown.</summary>
    Json: Boolean;
  end;

  TMcpRefactorTools = class
  public
    /// <summary>Ohne Kind die Umbauten der Stelle, sonst Vorschau bzw. Ergebnis des Umbaus. EMcpToolError bei
    /// unbekanntem oder gesperrtem Umbau, falschen Argumenten und Fehlern des Befehls.</summary>
    class function Run(AEdit: TMcpEditTools; const ASource: TMcpRefactorSource;
      const ARequest: TMcpRefactorRequest): string; static;
    /// <summary>Schlüssel der Umbauten mit Befehl, die refactor ausführen kann.</summary>
    class function CommandKinds: TArray<string>; static;
    /// <summary>Erwartete Argumente des Umbaus AKind als Text, z. B. "name: string"; '' ohne Argumente oder bei
    /// unbekanntem Schlüssel.</summary>
    class function ExpectedArguments(const AKind: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Mcp.Server,
  Atlas.Text.Json,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen.</summary>
  TRefactorToolsText = (NoRefactorings, RefactoringsAt, Blocked, Arguments, Choices, UnknownKind, Ambiguous,
    IsBlocked, UnknownArgument, WrongType, CommandFailed, NoMembers, UnknownMember, NoEdits, Notes, Candidates,
    RenameUnsupported, FromPreparation, Expected);

const
  cTexts: array[TRefactorToolsText] of TAtlasText = (
    (De: 'An %s gibt es keine Umbauten.'; En: 'There are no refactorings at %s.'),
    (De: 'Umbauten an %s (ausführen mit kind und args):'; En: 'Refactorings at %s (run with kind and args):'),
    (De: 'gesperrt: %s'; En: 'blocked: %s'),
    (De: 'args: %s'; En: 'args: %s'),
    (De: 'args: choices (Nummern, Vorgabe alle): %s'; En: 'args: choices (numbers, default all): %s'),
    (De: 'Kein Umbau "%s" an dieser Stelle.'; En: 'No refactoring "%s" at this position.'),
    (De: '"%s" passt auf mehrere Umbauten; mit title wählen:'; En: '"%s" matches several refactorings; choose with title:'),
    (De: '%s ist hier gesperrt: %s'; En: '%s is blocked here: %s'),
    (De: 'Unbekanntes Argument "%s". Erwartet: %s'; En: 'Unknown argument "%s". Expected: %s'),
    (De: 'Argument "%s" muss %s sein. Erwartet: %s'; En: 'Argument "%s" must be %s. Expected: %s'),
    (De: '%s geht nicht: %s'; En: '%s failed: %s'),
    (De: 'Keine Mitglieder gewählt; mit args.members wählen (Nummer oder Name):';
     En: 'No members chosen; choose with args.members (id or name):'),
    (De: 'Kein Mitglied "%s"; zur Wahl:'; En: 'No member "%s"; available:'),
    (De: '%s liefert keine Änderungen.'; En: '%s returns no changes.'),
    (De: 'Hinweise des Umbaus, bitte prüfen (%d):'; En: 'Notes of the refactoring, please check (%d):'),
    (De: 'Mitglieder (id, Name, Vorgabe):'; En: 'Members (id, name, default):'),
    (De: 'Umbenennen von Dateien geht über refactor nicht (%s).'; En: 'Renaming files is not supported by refactor (%s).'),
    (De: 'Vorgabe aus der Vorbereitung'; En: 'default from the preparation'),
    (De: 'keine'; En: 'none'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Präfix der Befehle, die das Plugin bearbeitet; der Server-Befehl hat das Präfix atlas.server.</summary>
  cClientPrefix = 'atlas.';
  cServerPrefix = 'atlas.server.';
  cPrepareSuffix = '.prepare';
  cChoicesArgument = 'choices';

type
  /// <summary>Wie die Argumente zum Befehl kommen: Slots ersetzen Argumente des Plugin-Befehls (Vorgabe ist dessen
  /// Wert), Prepared baut ein Anfrageobjekt aus der Vorbereitung und args.</summary>
  TRefactorShape = (Slots, Prepared);

  /// <summary>Umbau mit Befehl. Params: "Name:Typ@Stelle" bzw. bei Prepared "Name:Typ", durch ";" getrennt. Typen:
  /// string, boolean, ids (Nummern oder Namen der Mitglieder), names, parameters. Slot: Stelle der Anfrage im
  /// Befehl (nur Prepared).</summary>
  TRefactorKindSpec = record
    Key: string;
    Shape: TRefactorShape;
    Params: string;
    Slot: Integer;
  end;

const
  cKinds: array[0..16] of TRefactorKindSpec = (
    (Key: 'promoteVariable'; Shape: TRefactorShape.Slots; Params: 'name:string@2'; Slot: 0),
    (Key: 'invertBoolean'; Shape: TRefactorShape.Slots; Params: 'name:string@2'; Slot: 0),
    (Key: 'anonymousMethod'; Shape: TRefactorShape.Slots; Params: 'name:string@2'; Slot: 0),
    (Key: 'moveClass'; Shape: TRefactorShape.Slots; Params: 'name:string@2'; Slot: 0),
    (Key: 'methodKind'; Shape: TRefactorShape.Slots; Params: 'conversion:string@2'; Slot: 0),
    (Key: 'inlineAccessor'; Shape: TRefactorShape.Slots; Params: 'scope:string@2'; Slot: 0),
    (Key: 'propertyFromAccessors'; Shape: TRefactorShape.Slots; Params: 'calls:boolean@2'; Slot: 0),
    (Key: 'typeAlias'; Shape: TRefactorShape.Slots; Params: 'name:string@2;scope:string@3'; Slot: 0),
    (Key: 'inlineTypeAlias'; Shape: TRefactorShape.Slots; Params: ''; Slot: 0),
    (Key: 'enumTable'; Shape: TRefactorShape.Slots; Params: 'name:string@2;placement:string@3'; Slot: 0),
    (Key: 'enumTablesSync'; Shape: TRefactorShape.Slots; Params: ''; Slot: 0),
    (Key: 'createOverload'; Shape: TRefactorShape.Slots; Params: 'kind:string@2'; Slot: 0),
    (Key: 'changeSignature'; Shape: TRefactorShape.Prepared;
      Params: 'parameters:parameters;newParameter:string;virtualOverload:boolean'; Slot: 2),
    (Key: 'safeDelete'; Shape: TRefactorShape.Prepared; Params: 'overrides:boolean;cascade:boolean;force:boolean';
      Slot: 2),
    (Key: 'extractInterface'; Shape: TRefactorShape.Prepared; Params: 'name:string;unit:string;members:ids'; Slot: 2),
    (Key: 'extractSuperclass'; Shape: TRefactorShape.Prepared;
      Params: 'name:string;unit:string;members:ids;abstract:ids'; Slot: 2),
    (Key: 'moveMember'; Shape: TRefactorShape.Prepared; Params: 'members:ids;abstract:ids;targets:names;option:boolean';
      Slot: 3));

type
  /// <summary>Ein Argument eines Umbaus.</summary>
  TRefactorParam = record
    Name: string;
    TypeName: string;
    /// <summary>Stelle im Befehl (Slots); -1 bei Prepared.</summary>
    Slot: Integer;
  end;

  /// <summary>Ein Umbau der Stelle: die Code-Aktion (gehört der Liste) und wie sie auszuführen ist.</summary>
  TRefactorOffer = record
    Key: string;
    Title: string;
    Disabled: string;
    Action: TJSONObject;
    /// <summary>Eintrag in cKinds; -1 = Aktion mit Edits.</summary>
    Spec: Integer;
    /// <summary>Argumente des Plugin-Befehls; nil bei Aktionen mit Edits.</summary>
    Arguments: TJSONArray;
  end;

  /// <summary>Ergebnis eines Befehls: Änderungen, Hinweise, Vorschautext und die Vorbereitung (für den Bericht).
  /// </summary>
  TRefactorOutcome = record
    Changes: TMcpFileChanges;
    Notes: TArray<string>;
    Preview: string;
  end;

{ Argumente }

function SpecIndex(const AKey: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := Low(cKinds) to High(cKinds) do
  begin
    if SameText(cKinds[mIndex].Key, AKey) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function ParamsOf(const ASpec: TRefactorKindSpec): TArray<TRefactorParam>;
var
  mPart, mType: string;
  mParam: TRefactorParam;
begin
  Result := nil;
  for mPart in ASpec.Params.Split([';'], TStringSplitOptions.ExcludeEmpty) do
  begin
    mParam.Name := mPart.Split([':'])[0];
    mType := mPart.Split([':'])[1];
    mParam.TypeName := mType.Split(['@'])[0];
    mParam.Slot := -1;
    if Pos('@', mType) > 0 then
    begin
      mParam.Slot := StrToInt(mType.Split(['@'])[1]);
    end;
    Result := Result + [mParam];
  end;
end;

/// <summary>Schreibweise eines Argumenttyps; Listen mit ihrem Aufbau.</summary>
function TypeShape(const ATypeName: string): string;
begin
  case IndexStr(ATypeName, ['ids', 'names', 'numbers', 'parameters']) of
    0:
      Result := '[id | name, …]';
    1:
      Result := '[name, …]';
    2:
      Result := '[number, …]';
    3:
      Result := '[{origin?, name, type, modifier?, value?}, …]';
  else
    Result := ATypeName;
  end;
end;

/// <summary>Erwartete Form der Argumente, z. B. "name: string, scope: string".</summary>
function ExpectedForm(const AParams: TArray<TRefactorParam>): string;
var
  mParam: TRefactorParam;
begin
  Result := '';
  for mParam in AParams do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + mParam.Name + ': ' + TypeShape(mParam.TypeName);
  end;
  if Result = '' then
  begin
    Result := cTexts[TRefactorToolsText.Expected].Text;
  end;
end;

/// <summary>Passt AValue zum Typ ATypeName?</summary>
function TypeFits(AValue: TJSONValue; const ATypeName: string): Boolean;
begin
  if ATypeName = 'string' then
  begin
    // TJSONNumber erbt bis Delphi 12 (und unter FPC) von TJSONString.
    Exit((AValue is TJSONString) and not (AValue is TJSONNumber));
  end;
  if ATypeName = 'boolean' then
  begin
    Exit(AValue is TJSONBool);
  end;
  Result := AValue is TJSONArray;
end;

/// <summary>EMcpToolError bei unbekannten Argumenten und falschen Typen.</summary>
procedure CheckArgs(AArgs: TJSONObject; const AParams: TArray<TRefactorParam>);
var
  mPair: TJSONPair;
  mParam: TRefactorParam;
  mFound: Boolean;
begin
  if AArgs = nil then
  begin
    Exit;
  end;
  for mPair in AArgs do
  begin
    mFound := False;
    for mParam in AParams do
    begin
      if SameText(mParam.Name, mPair.JsonString.Value) then
      begin
        mFound := True;
        if not TypeFits(mPair.JsonValue, mParam.TypeName) then
        begin
          raise EMcpToolError.CreateFmt(cTexts[TRefactorToolsText.WrongType].Text,
            [mParam.Name, TypeShape(mParam.TypeName), ExpectedForm(AParams)]);
        end;
      end;
    end;
    if not mFound then
    begin
      raise EMcpToolError.CreateFmt(cTexts[TRefactorToolsText.UnknownArgument].Text, [mPair.JsonString.Value,
        ExpectedForm(AParams)]);
    end;
  end;
end;

/// <summary>Argument AName (ohne Groß-/Kleinschreibung); nil ohne.</summary>
function ArgOf(AArgs: TJSONObject; const AName: string): TJSONValue;
var
  mPair: TJSONPair;
begin
  Result := nil;
  if AArgs = nil then
  begin
    Exit;
  end;
  for mPair in AArgs do
  begin
    if SameText(mPair.JsonString.Value, AName) then
    begin
      Exit(mPair.JsonValue);
    end;
  end;
end;

{ Umbauten der Stelle }

/// <summary>Hat die Aktion Änderungen (changes oder documentChanges)?</summary>
function HasEdits(AAction: TJSONObject): Boolean;
var
  mEdit: TJSONObject;
  mPair: TJSONPair;
begin
  mEdit := TJsonRead.Obj(AAction, 'edit');
  if (TJsonRead.Items(mEdit, 'documentChanges') <> nil) and (TJsonRead.Items(mEdit, 'documentChanges').Count > 0) then
  begin
    Exit(True);
  end;
  if TJsonRead.Obj(mEdit, 'changes') <> nil then
  begin
    for mPair in TJsonRead.Obj(mEdit, 'changes') do
    begin
      if (mPair.JsonValue is TJSONArray) and (TJSONArray(mPair.JsonValue).Count > 0) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Umbau zur Aktion; False, wenn refactor sie nicht ausführen kann (Befehl nur im Plugin, nichts zu
/// ändern).</summary>
function OfferOf(AAction: TJSONObject; out AOffer: TRefactorOffer): Boolean;
var
  mCommand: string;
begin
  AOffer := Default(TRefactorOffer);
  AOffer.Action := AAction;
  AOffer.Title := TJsonRead.Text(AAction, 'title');
  AOffer.Disabled := TJsonRead.Text(TJsonRead.Obj(AAction, 'disabled'), 'reason');
  AOffer.Spec := -1;
  mCommand := TJsonRead.Text(TJsonRead.Obj(AAction, 'command'), 'command');
  if StartsStr(cClientPrefix, mCommand) and not StartsStr(cServerPrefix, mCommand) and
    (SpecIndex(Copy(mCommand, Length(cClientPrefix) + 1, MaxInt)) >= 0) then
  begin
    AOffer.Spec := SpecIndex(Copy(mCommand, Length(cClientPrefix) + 1, MaxInt));
    AOffer.Key := cKinds[AOffer.Spec].Key;
    AOffer.Arguments := TJsonRead.Items(TJsonRead.Obj(AAction, 'command'), 'arguments');
    Exit(True);
  end;
  // Aktionen mit Edits: Schlüssel ist die Kennung bzw. die LSP-Art, gewählt wird notfalls über den Titel.
  AOffer.Key := TJsonRead.Text(TJsonRead.Obj(AAction, 'data'), 'tag');
  if AOffer.Key = '' then
  begin
    AOffer.Key := TJsonRead.Text(AAction, 'kind');
  end;
  Result := HasEdits(AAction) or (AOffer.Disabled <> '');
end;

function OffersOf(AActions: TJSONArray): TArray<TRefactorOffer>;
var
  mItem: TJSONValue;
  mOffer: TRefactorOffer;
begin
  Result := nil;
  for mItem in AActions do
  begin
    if (mItem is TJSONObject) and OfferOf(TJSONObject(mItem), mOffer) then
    begin
      Result := Result + [mOffer];
    end;
  end;
end;

/// <summary>Abwählbare Teile der Aktion (data.choices), Titel je Teil.</summary>
function ChoiceTitles(AAction: TJSONObject): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if TJsonRead.Items(TJsonRead.Obj(AAction, 'data'), cChoicesArgument) = nil then
  begin
    Exit;
  end;
  for mItem in TJsonRead.Items(TJsonRead.Obj(AAction, 'data'), cChoicesArgument) do
  begin
    Result := Result + [TJsonRead.Text(TJsonRead.AsObject(mItem), 'title')];
  end;
end;

/// <summary>Argumente eines Umbaus mit ihren Vorgaben für die Liste.</summary>
function ArgumentsText(const AOffer: TRefactorOffer): string;
var
  mParam: TRefactorParam;
  mParts, mChoices: TArray<string>;
  mIndex: Integer;
begin
  if AOffer.Spec < 0 then
  begin
    mChoices := ChoiceTitles(AOffer.Action);
    Result := '';
    for mIndex := 0 to High(mChoices) do
    begin
      mChoices[mIndex] := Format('%d = %s', [mIndex + 1, mChoices[mIndex]]);
    end;
    if mChoices <> nil then
    begin
      Result := cTexts[TRefactorToolsText.Choices].Fmt([string.Join('; ', mChoices)]);
    end;
    Exit;
  end;
  mParts := nil;
  for mParam in ParamsOf(cKinds[AOffer.Spec]) do
  begin
    if (mParam.Slot >= 0) and (AOffer.Arguments <> nil) and (mParam.Slot < AOffer.Arguments.Count) then
    begin
      mParts := mParts + [Format('%s: %s = %s', [mParam.Name, mParam.TypeName,
        AOffer.Arguments.Items[mParam.Slot].ToJSON])];
    end
    else
    begin
      mParts := mParts + [Format('%s: %s', [mParam.Name, TypeShape(mParam.TypeName)])];
    end;
  end;
  Result := '';
  if mParts <> nil then
  begin
    Result := cTexts[TRefactorToolsText.Arguments].Fmt([string.Join(', ', mParts)]);
  end;
  if cKinds[AOffer.Spec].Shape = TRefactorShape.Prepared then
  begin
    Result := Result + ' (' + cTexts[TRefactorToolsText.FromPreparation].Text + ')';
  end;
end;

function Place(const ARequest: TMcpRefactorRequest): string;
begin
  Result := Format('%s:%d:%d', [ExtractFileName(ARequest.FileName), ARequest.Range.StartPos.Line + 1,
    ARequest.Range.StartPos.Character + 1]);
end;

function ListText(const AOffers: TArray<TRefactorOffer>; const ARequest: TMcpRefactorRequest): string;
var
  mOffer: TRefactorOffer;
  mLine: string;
begin
  if AOffers = nil then
  begin
    Exit(cTexts[TRefactorToolsText.NoRefactorings].Fmt([Place(ARequest)]));
  end;
  Result := cTexts[TRefactorToolsText.RefactoringsAt].Fmt([Place(ARequest)]);
  for mOffer in AOffers do
  begin
    mLine := Format('- %s – %s', [mOffer.Key, mOffer.Title]);
    if mOffer.Disabled <> '' then
    begin
      mLine := mLine + ' – ' + cTexts[TRefactorToolsText.Blocked].Fmt([mOffer.Disabled]);
    end
    else if ArgumentsText(mOffer) <> '' then
    begin
      mLine := mLine + ' – ' + ArgumentsText(mOffer);
    end;
    Result := Result + sLineBreak + mLine;
  end;
end;

function ListJson(const AOffers: TArray<TRefactorOffer>; const ARequest: TMcpRefactorRequest): string;
var
  mRoot, mItem, mArgument: TJSONObject;
  mList, mArguments: TJSONArray;
  mOffer: TRefactorOffer;
  mParam: TRefactorParam;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('file', ARequest.FileName);
    mRoot.AddPair('line', TJSONNumber.Create(ARequest.Range.StartPos.Line + 1));
    mRoot.AddPair('column', TJSONNumber.Create(ARequest.Range.StartPos.Character + 1));
    mList := TJSONArray.Create;
    mRoot.AddPair('refactorings', mList);
    for mOffer in AOffers do
    begin
      mItem := TJSONObject.Create;
      mList.AddElement(mItem);
      mItem.AddPair('kind', mOffer.Key);
      mItem.AddPair('title', mOffer.Title);
      if mOffer.Disabled <> '' then
      begin
        mItem.AddPair('disabled', mOffer.Disabled);
      end;
      mArguments := TJSONArray.Create;
      mItem.AddPair('args', mArguments);
      if mOffer.Spec < 0 then
      begin
        if ChoiceTitles(mOffer.Action) <> nil then
        begin
          mArgument := TJSONObject.Create;
          mArgument.AddPair('name', cChoicesArgument);
          mArgument.AddPair('type', 'numbers');
          mArgument.AddPair('choices', TJsonBuild.Strings(ChoiceTitles(mOffer.Action)));
          mArguments.AddElement(mArgument);
        end;
        Continue;
      end;
      for mParam in ParamsOf(cKinds[mOffer.Spec]) do
      begin
        mArgument := TJSONObject.Create;
        mArgument.AddPair('name', mParam.Name);
        mArgument.AddPair('type', mParam.TypeName);
        if (mParam.Slot >= 0) and (mOffer.Arguments <> nil) and (mParam.Slot < mOffer.Arguments.Count) then
        begin
          mArgument.AddPair('default', mOffer.Arguments.Items[mParam.Slot].Clone as TJSONValue);
        end;
        mArguments.AddElement(mArgument);
      end;
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

/// <summary>Gibt args die Stelle vor, in der sich gleichartige Angebote unterscheiden (createOverload mit kind,
/// methodKind mit conversion), passt das Angebot mit diesem Wert; sonst das erste, die Stelle wird ja ersetzt.
/// Ohne vorgegebene Stelle nil.</summary>
function SlotChoice(const AFound: TArray<TRefactorOffer>; AArgs: TJSONObject): TArray<TRefactorOffer>;
var
  mOffer: TRefactorOffer;
  mParam: TRefactorParam;
  mValue: TJSONValue;
begin
  Result := nil;
  for mOffer in AFound do
  begin
    if (mOffer.Spec < 0) or (mOffer.Spec <> AFound[0].Spec) or (mOffer.Disabled <> '') then
    begin
      Exit(nil);
    end;
  end;
  for mParam in ParamsOf(cKinds[AFound[0].Spec]) do
  begin
    mValue := ArgOf(AArgs, mParam.Name);
    if (mParam.Slot < 0) or (mValue = nil) then
    begin
      Continue;
    end;
    for mOffer in AFound do
    begin
      if (mOffer.Arguments <> nil) and (mParam.Slot < mOffer.Arguments.Count) and
        (mOffer.Arguments.Items[mParam.Slot].ToJSON = mValue.ToJSON) then
      begin
        Result := [mOffer];
        Exit;
      end;
    end;
    Result := [AFound[0]];
  end;
end;

/// <summary>Der gewünschte Umbau; EMcpToolError, wenn es ihn nicht gibt, er mehrdeutig oder gesperrt ist.</summary>
function Choose(const AOffers: TArray<TRefactorOffer>; const ARequest: TMcpRefactorRequest): TRefactorOffer;
var
  mOffer: TRefactorOffer;
  mFound, mChoice: TArray<TRefactorOffer>;
  mTitles: TArray<string>;
begin
  mFound := nil;
  for mOffer in AOffers do
  begin
    if (SameText(mOffer.Key, ARequest.Kind) or SameText(mOffer.Title, ARequest.Kind)) and
      ((ARequest.Title = '') or SameText(mOffer.Title, ARequest.Title)) then
    begin
      mFound := mFound + [mOffer];
    end;
  end;
  if mFound = nil then
  begin
    raise EMcpToolError.Create(cTexts[TRefactorToolsText.UnknownKind].Fmt([ARequest.Kind]) + sLineBreak +
      ListText(AOffers, ARequest));
  end;
  if Length(mFound) > 1 then
  begin
    mChoice := SlotChoice(mFound, ARequest.Args);
    if mChoice <> nil then
    begin
      mFound := mChoice;
    end;
  end;
  if Length(mFound) > 1 then
  begin
    mTitles := nil;
    for mOffer in mFound do
    begin
      mTitles := mTitles + ['- ' + mOffer.Title];
    end;
    raise EMcpToolError.Create(cTexts[TRefactorToolsText.Ambiguous].Fmt([ARequest.Kind]) + sLineBreak +
      string.Join(sLineBreak, mTitles));
  end;
  Result := mFound[0];
  if Result.Disabled <> '' then
  begin
    raise EMcpToolError.Create(cTexts[TRefactorToolsText.IsBlocked].Fmt([Result.Title, Result.Disabled]));
  end;
end;

{ WorkspaceEdit lesen }

function AsArray(AValue: TJSONValue): TJSONArray;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    Result := TJSONArray(AValue);
  end;
end;

procedure AddTextEdits(var AChanges: TMcpFileChanges; const AFileName: string; AEdits: TJSONArray;
  const AKeep: TFunc<Integer, Boolean>);
var
  mIndex: Integer;
  mEdit: TJSONObject;
begin
  if AEdits = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AEdits.Count - 1 do
  begin
    mEdit := TJsonRead.AsObject(AEdits.Items[mIndex]);
    if (mEdit <> nil) and (not Assigned(AKeep) or AKeep(mIndex)) then
    begin
      AChanges.Edits := AChanges.Edits + [TMcpFileEdit.Create(AFileName,
        TLspPositions.ReadRange(mEdit.GetValue('range')), TJsonRead.Text(mEdit, 'newText'))];
    end;
  end;
end;

procedure AddDocumentChange(var AChanges: TMcpFileChanges; AChange: TJSONObject);
var
  mKind, mFileName: string;
begin
  mKind := TJsonRead.Text(AChange, 'kind');
  mFileName := TDocumentUris.ToPath(TJsonRead.Text(AChange, 'uri'));
  if mKind = 'create' then
  begin
    AChanges.Created := AChanges.Created + [TMcpNewFile.Create(mFileName, '')];
  end
  else if mKind = 'delete' then
  begin
    AChanges.Deleted := AChanges.Deleted + [mFileName];
  end
  else if mKind <> '' then
  begin
    raise EMcpToolError.Create(cTexts[TRefactorToolsText.RenameUnsupported].Fmt([mFileName]));
  end
  else
  begin
    AddTextEdits(AChanges, TDocumentUris.ToPath(TJsonRead.Text(TJsonRead.Obj(AChange, 'textDocument'), 'uri')),
      TJsonRead.Items(AChange, 'edits'), nil);
  end;
end;

/// <summary>Änderungen eines WorkspaceEdit; AKeep entscheidet je Edit des Dokuments AUri (abwählbare Teile).
/// </summary>
function ChangesOf(AEdit: TJSONObject; const AUri: string; const AKeep: TFunc<Integer, Boolean>): TMcpFileChanges;
var
  mPair: TJSONPair;
  mItem: TJSONValue;
begin
  Result := Default(TMcpFileChanges);
  if TJsonRead.Obj(AEdit, 'changes') <> nil then
  begin
    for mPair in TJsonRead.Obj(AEdit, 'changes') do
    begin
      if SameText(mPair.JsonString.Value, AUri) then
      begin
        AddTextEdits(Result, TDocumentUris.ToPath(mPair.JsonString.Value), AsArray(mPair.JsonValue), AKeep);
      end
      else
      begin
        AddTextEdits(Result, TDocumentUris.ToPath(mPair.JsonString.Value), AsArray(mPair.JsonValue), nil);
      end;
    end;
  end;
  if TJsonRead.Items(AEdit, 'documentChanges') <> nil then
  begin
    for mItem in TJsonRead.Items(AEdit, 'documentChanges') do
    begin
      if mItem is TJSONObject then
      begin
        AddDocumentChange(Result, TJSONObject(mItem));
      end;
    end;
  end;
end;

{ Aktionen mit Edits }

/// <summary>Gewählte Teile (ab 0) aus args.choices (Nummern ab 1); ohne Angabe alle.</summary>
function ChosenParts(AArgs: TJSONObject; ACount: Integer): TArray<Boolean>;
var
  mItem: TJSONValue;
  mIndex: Integer;
begin
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result[mIndex] := not (ArgOf(AArgs, cChoicesArgument) is TJSONArray);
  end;
  if not (ArgOf(AArgs, cChoicesArgument) is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(ArgOf(AArgs, cChoicesArgument)) do
  begin
    if (mItem is TJSONNumber) and (TJSONNumber(mItem).AsInt >= 1) and (TJSONNumber(mItem).AsInt <= ACount) then
    begin
      Result[TJSONNumber(mItem).AsInt - 1] := True;
    end;
  end;
end;

/// <summary>Bleibt Edit AIndex des Dokuments mit den gewählten Teilen AChosen? editChoices nennt je Edit die
/// Teile, die alle gewählt sein müssen.</summary>
function KeepEdit(AEditChoices: TJSONArray; const AChosen: TArray<Boolean>; AIndex: Integer): Boolean;
var
  mItem: TJSONValue;
begin
  Result := True;
  if (AEditChoices = nil) or (AIndex >= AEditChoices.Count) or not (AEditChoices.Items[AIndex] is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AEditChoices.Items[AIndex]) do
  begin
    if (mItem is TJSONNumber) and (TJSONNumber(mItem).AsInt <= High(AChosen)) and
      not AChosen[TJSONNumber(mItem).AsInt] then
    begin
      Exit(False);
    end;
  end;
end;

function EditKeeper(AEditChoices: TJSONArray; const AChosen: TArray<Boolean>): TFunc<Integer, Boolean>;
begin
  Result :=
    function(AIndex: Integer): Boolean
    begin
      Result := KeepEdit(AEditChoices, AChosen, AIndex);
    end;
end;

function EditOutcome(const AOffer: TRefactorOffer; AArgs: TJSONObject; const AUri: string): TRefactorOutcome;
var
  mParams: TArray<TRefactorParam>;
  mData: TJSONObject;
begin
  mParams := nil;
  if ChoiceTitles(AOffer.Action) <> nil then
  begin
    SetLength(mParams, 1);
    mParams[0].Name := cChoicesArgument;
    mParams[0].TypeName := 'numbers';
    mParams[0].Slot := -1;
  end;
  CheckArgs(AArgs, mParams);
  mData := TJsonRead.Obj(AOffer.Action, 'data');
  Result := Default(TRefactorOutcome);
  Result.Preview := TJsonRead.Text(mData, 'preview');
  Result.Changes := ChangesOf(TJsonRead.Obj(AOffer.Action, 'edit'), AUri,
    EditKeeper(TJsonRead.Items(mData, 'editChoices'), ChosenParts(AArgs, Length(ChoiceTitles(AOffer.Action)))));
end;


{ Umbauten mit Befehl }

/// <summary>Wert aus args für die Stelle ASlot; nil, wenn args sie nicht setzt.</summary>
function SlotOverride(const AParams: TArray<TRefactorParam>; AArgs: TJSONObject; ASlot: Integer): TJSONValue;
var
  mParam: TRefactorParam;
begin
  for mParam in AParams do
  begin
    if (mParam.Slot = ASlot) and (ArgOf(AArgs, mParam.Name) <> nil) then
    begin
      Exit(ArgOf(AArgs, mParam.Name));
    end;
  end;
  Result := nil;
end;

/// <summary>Die ersten ACount Argumente des Plugin-Befehls, Stellen aus args ersetzt; fehlende als null. Der
/// Aufrufer übernimmt das Array.</summary>
function CommandArguments(const AOffer: TRefactorOffer; const AParams: TArray<TRefactorParam>; AArgs: TJSONObject;
  ACount: Integer): TJSONArray;
var
  mIndex: Integer;
  mValue: TJSONValue;
begin
  Result := TJSONArray.Create;
  for mIndex := 0 to ACount - 1 do
  begin
    mValue := SlotOverride(AParams, AArgs, mIndex);
    if (mValue = nil) and (AOffer.Arguments <> nil) and (mIndex < AOffer.Arguments.Count) then
    begin
      mValue := AOffer.Arguments.Items[mIndex];
    end;
    if mValue = nil then
    begin
      Result.AddElement(TJSONNull.Create);
    end
    else
    begin
      Result.AddElement(mValue.Clone as TJSONValue);
    end;
  end;
end;

/// <summary>Zahl der Argumente bei Slots: die des Plugin-Befehls, mindestens bis zur höchsten Stelle.</summary>
function SlotCount(const AOffer: TRefactorOffer; const AParams: TArray<TRefactorParam>): Integer;
var
  mParam: TRefactorParam;
begin
  Result := 0;
  if AOffer.Arguments <> nil then
  begin
    Result := AOffer.Arguments.Count;
  end;
  for mParam in AParams do
  begin
    if mParam.Slot + 1 > Result then
    begin
      Result := mParam.Slot + 1;
    end;
  end;
end;

/// <summary>Mitglieder der Vorbereitung als Text: Nummer, Name, gewählt bzw. gesperrt.</summary>
function CandidatesText(ACandidates: TJSONArray): string;
var
  mItem: TJSONValue;
  mCandidate: TJSONObject;
  mLine: string;
begin
  Result := cTexts[TRefactorToolsText.Candidates].Text;
  if ACandidates = nil then
  begin
    Exit;
  end;
  for mItem in ACandidates do
  begin
    mCandidate := TJsonRead.AsObject(mItem);
    mLine := Format('- %d %s', [TJsonRead.Int(mCandidate, 'id'), TJsonRead.Text(mCandidate, 'name')]);
    if TJsonRead.Flag(mCandidate, 'checked') then
    begin
      mLine := mLine + ' (*)';
    end;
    if not TJsonRead.FlagOr(mCandidate, 'enabled', True) then
    begin
      mLine := mLine + ' – ' + cTexts[TRefactorToolsText.Blocked].Fmt([TJsonRead.Text(mCandidate, 'reason')]);
    end;
    Result := Result + sLineBreak + mLine;
  end;
end;

/// <summary>Nummer des Mitglieds AValue (Nummer oder Name) unter ACandidates; EMcpToolError, wenn es fehlt.</summary>
function MemberId(AValue: TJSONValue; ACandidates: TJSONArray): Integer;
var
  mItem: TJSONValue;
begin
  if ACandidates <> nil then
  begin
    for mItem in ACandidates do
    begin
      if ((AValue is TJSONNumber) and (TJsonRead.Int(TJsonRead.AsObject(mItem), 'id') = TJSONNumber(AValue).AsInt)) or
        ((AValue is TJSONString) and SameText(TJsonRead.Text(TJsonRead.AsObject(mItem), 'name'), AValue.Value)) then
      begin
        Exit(TJsonRead.Int(TJsonRead.AsObject(mItem), 'id'));
      end;
    end;
  end;
  raise EMcpToolError.Create(cTexts[TRefactorToolsText.UnknownMember].Fmt([AValue.Value]) + sLineBreak +
    CandidatesText(ACandidates));
end;

function ContainsId(AIds: TJSONArray; AId: Integer): Boolean;
var
  mItem: TJSONValue;
begin
  for mItem in AIds do
  begin
    if (mItem is TJSONNumber) and (TJSONNumber(mItem).AsInt = AId) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Nummern aus args; ohne args die gewählten Kandidaten (checked), bei "abstract" die als abstrakt
/// vorgeschlagenen unter den gewählten Mitgliedern AChosen.</summary>
function IdsValue(const AParam: TRefactorParam; AArg: TJSONValue; ACandidates: TJSONArray;
  AChosen: TJSONArray): TJSONArray;
var
  mItem: TJSONValue;
  mCandidate: TJSONObject;
  mField: string;
begin
  Result := TJSONArray.Create;
  try
    if AArg is TJSONArray then
    begin
      for mItem in TJSONArray(AArg) do
      begin
        Result.Add(MemberId(mItem, ACandidates));
      end;
      Exit;
    end;
    mField := 'checked';
    if AParam.Name = 'abstract' then
    begin
      mField := 'abstract';
    end;
    if ACandidates = nil then
    begin
      Exit;
    end;
    for mItem in ACandidates do
    begin
      mCandidate := TJsonRead.AsObject(mItem);
      if TJsonRead.Flag(mCandidate, mField) and TJsonRead.FlagOr(mCandidate, 'enabled', True) and
        ((AChosen = nil) or ContainsId(AChosen, TJsonRead.Int(mCandidate, 'id'))) then
      begin
        Result.Add(TJsonRead.Int(mCandidate, 'id'));
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

/// <summary>Namen aus args; ohne args die gewählten Ziele der Vorbereitung.</summary>
function NamesValue(AArg: TJSONValue; ATargets: TJSONArray): TJSONArray;
var
  mItem: TJSONValue;
begin
  if AArg is TJSONArray then
  begin
    Exit(AArg.Clone as TJSONArray);
  end;
  Result := TJSONArray.Create;
  if ATargets = nil then
  begin
    Exit;
  end;
  for mItem in ATargets do
  begin
    if TJsonRead.Flag(TJsonRead.AsObject(mItem), 'checked') then
    begin
      Result.Add(TJsonRead.Text(TJsonRead.AsObject(mItem), 'name'));
    end;
  end;
end;

/// <summary>Stelle des Parameters AName unter den bisherigen; -1 = neu.</summary>
function OriginOf(const AName: string; AOld: TJSONArray): Integer;
var
  mIndex: Integer;
begin
  if AOld <> nil then
  begin
    for mIndex := 0 to AOld.Count - 1 do
    begin
      if SameText(TJsonRead.Text(TJsonRead.AsObject(AOld.Items[mIndex]), 'name'), AName) then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := -1;
end;

/// <summary>Ein Parameter der neuen Signatur: Felder aus AItem, fehlende vom bisherigen Parameter AOrigin.</summary>
function ParameterJson(AItem: TJSONObject; AOld: TJSONArray; AOrigin: Integer): TJSONObject;
var
  mOld: TJSONObject;
  mField, mText: string;
begin
  mOld := nil;
  if (AOld <> nil) and (AOrigin >= 0) and (AOrigin < AOld.Count) then
  begin
    mOld := TJsonRead.AsObject(AOld.Items[AOrigin]);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('origin', TJSONNumber.Create(AOrigin));
  for mField in TArray<string>.Create('name', 'type', 'modifier') do
  begin
    if not TJsonRead.TryText(AItem, mField, mText) then
    begin
      mText := TJsonRead.Text(mOld, mField);
    end;
    Result.AddPair(mField, mText);
  end;
  Result.AddPair('value', TJsonRead.Text(AItem, 'value'));
end;

/// <summary>parameters der neuen Signatur: aus args (origin fehlt: nach dem Namen) bzw. die bisherigen.</summary>
function ParametersValue(AArg: TJSONValue; AOld: TJSONArray): TJSONArray;
var
  mIndex, mOrigin: Integer;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  if not (AArg is TJSONArray) then
  begin
    if AOld <> nil then
    begin
      for mIndex := 0 to AOld.Count - 1 do
      begin
        Result.AddElement(ParameterJson(nil, AOld, mIndex));
      end;
    end;
    Exit;
  end;
  for mIndex := 0 to TJSONArray(AArg).Count - 1 do
  begin
    mItem := TJsonRead.AsObject(TJSONArray(AArg).Items[mIndex]);
    mOrigin := TJsonRead.IntOr(mItem, 'origin', OriginOf(TJsonRead.Text(mItem, 'name'), AOld));
    Result.AddElement(ParameterJson(mItem, AOld, mOrigin));
  end;
end;

/// <summary>Vorgabe eines einfachen Werts: das gleichnamige Feld der Vorbereitung (option: option.value), sonst
/// leer bzw. false.</summary>
function PlainValue(const AParam: TRefactorParam; AArg: TJSONValue; APrepared: TJSONObject): TJSONValue;
var
  mPrepared: TJSONValue;
begin
  if AArg <> nil then
  begin
    Exit(AArg.Clone as TJSONValue);
  end;
  mPrepared := TJsonRead.Value(APrepared, AParam.Name);
  if AParam.Name = 'option' then
  begin
    mPrepared := TJsonRead.Value(TJsonRead.Obj(APrepared, 'option'), 'value');
  end;
  if (AParam.TypeName = 'boolean') and (mPrepared is TJSONBool) then
  begin
    Exit(mPrepared.Clone as TJSONValue);
  end;
  if AParam.TypeName = 'boolean' then
  begin
    Exit(TJSONBool.Create(False));
  end;
  if mPrepared is TJSONString then
  begin
    Exit(mPrepared.Clone as TJSONValue);
  end;
  Result := TJSONString.Create('');
end;

function PreparedValue(const AParam: TRefactorParam; AArg: TJSONValue; APrepared, ARequest: TJSONObject): TJSONValue;
begin
  if AParam.TypeName = 'ids' then
  begin
    Exit(IdsValue(AParam, AArg, TJsonRead.Items(APrepared, 'candidates'), TJsonRead.Items(ARequest, 'members')));
  end;
  if AParam.TypeName = 'names' then
  begin
    Exit(NamesValue(AArg, TJsonRead.Items(APrepared, 'targets')));
  end;
  if AParam.TypeName = 'parameters' then
  begin
    Exit(ParametersValue(AArg, TJsonRead.Items(APrepared, 'parameters')));
  end;
  Result := PlainValue(AParam, AArg, APrepared);
end;

/// <summary>Anfrage aus args und den Vorgaben der Vorbereitung; EMcpToolError ohne gewählte Mitglieder. Der
/// Aufrufer übernimmt das Objekt.</summary>
function PreparedRequest(const AParams: TArray<TRefactorParam>; APrepared, AArgs: TJSONObject): TJSONObject;
var
  mParam: TRefactorParam;
begin
  Result := TJSONObject.Create;
  try
    for mParam in AParams do
    begin
      Result.AddPair(mParam.Name, PreparedValue(mParam, ArgOf(AArgs, mParam.Name), APrepared, Result));
    end;
    if (TJsonRead.Items(Result, 'members') <> nil) and (TJsonRead.Items(Result, 'members').Count = 0) then
    begin
      raise EMcpToolError.Create(cTexts[TRefactorToolsText.NoMembers].Text + sLineBreak +
        CandidatesText(TJsonRead.Items(APrepared, 'candidates')));
    end;
  except
    Result.Free;
    raise;
  end;
end;

/// <summary>Führt ACommand aus; Fehler des Befehls als EMcpToolError samt erwarteter Argumente.</summary>
function RunCommand(const ASource: TMcpRefactorSource; const ACommand: string; AArguments: TJSONArray;
  const ATitle: string; const AParams: TArray<TRefactorParam>): TJSONValue;
begin
  try
    Result := ASource.Execute(ACommand, AArguments);
  except
    on E: EJsonRpcError do
      raise EMcpToolError.Create(cTexts[TRefactorToolsText.CommandFailed].Fmt([ATitle, E.Message]) + sLineBreak +
        cTexts[TRefactorToolsText.Arguments].Fmt([ExpectedForm(AParams)]));
  end;
end;

/// <summary>Argumente des Server-Befehls bei Prepared: die des Plugin-Befehls bis zur Stelle der Anfrage, dann
/// die Anfrage. AInfo: Mitglieder der Vorbereitung für den Bericht ('' ohne). Der Aufrufer übernimmt das Array.
/// </summary>
function PreparedArguments(const ASource: TMcpRefactorSource; const AOffer: TRefactorOffer;
  const AParams: TArray<TRefactorParam>; AArgs: TJSONObject; out AInfo: string): TJSONArray;
var
  mSpec: TRefactorKindSpec;
  mPrepareArguments: TJSONArray;
  mPrepared: TJSONValue;
begin
  mSpec := cKinds[AOffer.Spec];
  AInfo := '';
  mPrepareArguments := CommandArguments(AOffer, AParams, AArgs, mSpec.Slot);
  try
    mPrepared := RunCommand(ASource, cServerPrefix + mSpec.Key + cPrepareSuffix, mPrepareArguments, AOffer.Title,
      AParams);
  finally
    mPrepareArguments.Free;
  end;
  try
    if (TJsonRead.Items(TJsonRead.AsObject(mPrepared), 'candidates') <> nil) and
      (TJsonRead.Items(TJsonRead.AsObject(mPrepared), 'candidates').Count > 0) then
    begin
      AInfo := CandidatesText(TJsonRead.Items(TJsonRead.AsObject(mPrepared), 'candidates'));
    end;
    Result := CommandArguments(AOffer, AParams, AArgs, mSpec.Slot);
    try
      Result.AddElement(PreparedRequest(AParams, TJsonRead.AsObject(mPrepared), AArgs));
    except
      Result.Free;
      raise;
    end;
  finally
    mPrepared.Free;
  end;
end;

/// <summary>Änderungen, Hinweise und Vorschau aus der Antwort {edit, warnings, preview} eines Befehls.</summary>
function AnswerOutcome(AAnswer: TJSONValue): TRefactorOutcome;
var
  mAnswer: TJSONObject;
begin
  mAnswer := TJsonRead.AsObject(AAnswer);
  Result := Default(TRefactorOutcome);
  Result.Changes := ChangesOf(TJsonRead.Obj(mAnswer, 'edit'), '', nil);
  Result.Notes := TJsonRead.Strings(mAnswer, 'warnings');
  Result.Preview := TJsonRead.Text(mAnswer, 'preview');
end;

function CommandOutcome(const ASource: TMcpRefactorSource; const AOffer: TRefactorOffer; AArgs: TJSONObject;
  out AInfo: string): TRefactorOutcome;
var
  mParams: TArray<TRefactorParam>;
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  mParams := ParamsOf(cKinds[AOffer.Spec]);
  CheckArgs(AArgs, mParams);
  AInfo := '';
  if cKinds[AOffer.Spec].Shape = TRefactorShape.Prepared then
  begin
    mArguments := PreparedArguments(ASource, AOffer, mParams, AArgs, AInfo);
  end
  else
  begin
    mArguments := CommandArguments(AOffer, mParams, AArgs, SlotCount(AOffer, mParams));
  end;
  try
    mAnswer := RunCommand(ASource, cServerPrefix + cKinds[AOffer.Spec].Key, mArguments, AOffer.Title, mParams);
  finally
    mArguments.Free;
  end;
  try
    Result := AnswerOutcome(mAnswer);
  finally
    mAnswer.Free;
  end;
end;

{ Bericht }

function NotesText(const ANotes: TArray<string>): string;
var
  mNote: string;
begin
  Result := '';
  if ANotes = nil then
  begin
    Exit;
  end;
  Result := sLineBreak + sLineBreak + cTexts[TRefactorToolsText.Notes].Fmt([Length(ANotes)]);
  for mNote in ANotes do
  begin
    Result := Result + sLineBreak + '- ' + mNote;
  end;
end;

function ChangesJson(const AChanges: TMcpFileChanges): TJSONObject;
var
  mEdits, mCreated: TJSONArray;
  mEdit: TMcpFileEdit;
  mFile: TMcpNewFile;
  mItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  mEdits := TJSONArray.Create;
  Result.AddPair('edits', mEdits);
  for mEdit in AChanges.Edits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('file', mEdit.FileName);
    mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
    mItem.AddPair('newText', mEdit.NewText);
    mEdits.AddElement(mItem);
  end;
  mCreated := TJSONArray.Create;
  Result.AddPair('created', mCreated);
  for mFile in AChanges.Created do
  begin
    mCreated.Add(mFile.FileName);
  end;
  Result.AddPair('deleted', TJsonBuild.Strings(AChanges.Deleted));
end;

function ReportJson(const AOffer: TRefactorOffer; const AOutcome: TRefactorOutcome; const AText: string;
  ADryRun: Boolean): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('kind', AOffer.Key);
    mRoot.AddPair('title', AOffer.Title);
    mRoot.AddPair('dryRun', TJSONBool.Create(ADryRun));
    mRoot.AddPair('preview', AOutcome.Preview);
    mRoot.AddPair('notes', TJsonBuild.Strings(AOutcome.Notes));
    mRoot.AddPair('changes', ChangesJson(AOutcome.Changes));
    mRoot.AddPair('report', AText);
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

function Report(AEdit: TMcpEditTools; const AOffer: TRefactorOffer; const AOutcome: TRefactorOutcome;
  const AInfo: string; const ARequest: TMcpRefactorRequest): string;
var
  mHead: string;
begin
  if AOutcome.Changes.Count = 0 then
  begin
    raise EMcpToolError.Create(cTexts[TRefactorToolsText.NoEdits].Fmt([AOffer.Title]) + NotesText(AOutcome.Notes));
  end;
  mHead := AOffer.Title;
  if AOutcome.Preview <> '' then
  begin
    mHead := mHead + sLineBreak + AOutcome.Preview;
  end;
  if AInfo <> '' then
  begin
    mHead := mHead + sLineBreak + AInfo;
  end;
  Result := mHead + sLineBreak + AEdit.ApplyChanges('refactor', AOutcome.Changes, ARequest.DryRun) +
    NotesText(AOutcome.Notes);
  if ARequest.Json then
  begin
    Result := ReportJson(AOffer, AOutcome, Result, ARequest.DryRun);
  end;
end;

{ TMcpRefactorTools }

class function TMcpRefactorTools.Run(AEdit: TMcpEditTools; const ASource: TMcpRefactorSource;
  const ARequest: TMcpRefactorRequest): string;
var
  mActions: TJSONArray;
  mOffers: TArray<TRefactorOffer>;
  mOffer: TRefactorOffer;
  mOutcome: TRefactorOutcome;
  mInfo: string;
begin
  mActions := ASource.Actions(ARequest.FileName, ARequest.Range);
  try
    mOffers := OffersOf(mActions);
    if (ARequest.Kind = '') and ARequest.Json then
    begin
      Exit(ListJson(mOffers, ARequest));
    end;
    if ARequest.Kind = '' then
    begin
      Exit(ListText(mOffers, ARequest));
    end;
    mOffer := Choose(mOffers, ARequest);
    mInfo := '';
    if mOffer.Spec < 0 then
    begin
      mOutcome := EditOutcome(mOffer, ARequest.Args, TDocumentUris.FromPath(ARequest.FileName));
    end
    else
    begin
      mOutcome := CommandOutcome(ASource, mOffer, ARequest.Args, mInfo);
    end;
    Result := Report(AEdit, mOffer, mOutcome, mInfo, ARequest);
  finally
    mActions.Free;
  end;
end;

class function TMcpRefactorTools.CommandKinds: TArray<string>;
var
  mSpec: TRefactorKindSpec;
begin
  Result := nil;
  for mSpec in cKinds do
  begin
    Result := Result + [mSpec.Key];
  end;
end;

class function TMcpRefactorTools.ExpectedArguments(const AKind: string): string;
begin
  Result := '';
  if (SpecIndex(AKind) >= 0) and (cKinds[SpecIndex(AKind)].Params <> '') then
  begin
    Result := ExpectedForm(ParamsOf(cKinds[SpecIndex(AKind)]));
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.RefactorTools', cTexts);

end.
