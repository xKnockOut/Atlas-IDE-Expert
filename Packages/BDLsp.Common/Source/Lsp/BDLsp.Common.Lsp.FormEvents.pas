unit BDLsp.Common.Lsp.FormEvents;

// Ereignis-Handler aus der Formulardatei anlegen (#111). Steht der Cursor in
// einer .dfm/.fmx hinter "OnClick = ", schlägt die Vervollständigung die
// Methoden der Formularklasse vor, deren Parameter zum Typ des Ereignisses
// passen (TNotifyEvent → (Sender: TObject)), und einen Eintrag "neu", der die
// Methode anlegt.
//
// Die Signatur kommt aus dem Typ der Event-Property (TPublishedMembers) und
// dessen Deklaration im Index; ohne Index ist TNotifyEvent bekannt.
// additionalTextEdits dürfen nur die Formulardatei ändern. Das Anlegen in der
// Unit erledigt daher der Befehl CreateCommand am Eintrag: Er fügt die
// Deklaration im ersten (published) Abschnitt der Formularklasse ein, erzeugt
// den Rumpf über die Klassenvervollständigung (#42) und schickt beides per
// workspace/applyEdit an den Editor. Zeilenenden der Unit bleiben erhalten.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Lsp.PublishedMembers,
  BDLsp.Common.Lsp.Completion;

type
  /// <summary>Ereignis-Eigenschaft unter dem Cursor in der Formulardatei.</summary>
  TFormEventContext = record
    FormClass: string;
    ComponentName: string;
    ComponentClass: string;
    EventName: string;
    /// <summary>Schon getippter Anfang des Methodennamens.</summary>
    Prefix: string;
  end;

  TFormEvents = class
  public const
    CreateCommand = 'betterdelphilsp.createEventHandler';
    /// <summary>Signatur, wenn der Ereignistyp nicht im Index steht.</summary>
    NotifyTail = '(Sender: TObject)';
  public
    /// <summary>Steht APosition hinter "OnXxx = " in einer Komponente der Formulardatei?</summary>
    class function ContextAt(const AFormText: string; const APosition: TTextPosition;
      out AContext: TFormEventContext): Boolean; static;
    /// <summary>Parameter und ggf. Rückgabetyp des Ereignisses, z. B. "(Sender: TObject)".</summary>
    class function EventTail(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
      const AComponentClass, AEventName: string; out ATail: string): Boolean; static;
    /// <summary>Methoden der Formularklasse mit passender Signatur.</summary>
    class function MatchingMethods(const AUnitText, AFormClass, ATail: string): TArray<string>; static;
    /// <summary>Komponentenname + Ereignis ohne On; bei Vergabe mit angehängter Ziffer.</summary>
    class function NewMethodName(const AUnitText, AFormClass, AComponentName, AEventName: string): string; static;
    /// <summary>Deklaration im ersten Abschnitt der Formularklasse und leerer Rumpf.</summary>
    class function CreateHandler(const AUnitText, AFormClass, AMethodName, ATail: string;
      out AEdits: TArray<TRuleEdit>): Boolean; static;
    /// <summary>Vervollständigung für die Formulardatei; False außerhalb eines Ereignisses.</summary>
    class function Items(const AFormFile, AFormText, AUnitText: string; const APosition: TTextPosition;
      const AIndex: ISymbolIndex; const AReadText: TMemberReadText; out AItems: TCompletionItems): Boolean; static;
    /// <summary>workspace/applyEdit für CreateCommand mit den Argumenten [Unit-URI, Klasse, Name, Signatur];
    /// nil, wenn nichts anzulegen ist. Der Aufrufer übernimmt das Objekt.</summary>
    class function ApplyEditParams(const AArguments: TJSONArray; const AReadText: TMemberReadText): TJSONObject; static;
  end;

implementation

uses
  System.StrUtils,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Index.Extractor,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Dfm.Contract,
  BDLsp.Common.Dfm.Parser,
  BDLsp.Common.Editing.CodeActions,
  BDLsp.Common.Editing.ClassCompletion,
  BDLsp.Common.Lsp.FileOperations;

const
  // CompletionItemKind des LSP.
  KindMethod = 2;
  KindEvent = 23;

/// <summary>Zerlegt AText an ADelimiter.</summary>
function SplitAt(const AText: string; ADelimiter: Char): TArray<string>;
var
  Index, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for Index := 1 to Length(AText) + 1 do
    if (Index > Length(AText)) or (AText[Index] = ADelimiter) then
    begin
      Result := Result + [Copy(AText, Start, Index - Start)];
      Start := Index + 1;
    end;
end;

function LinesOf(const AText: string): TArray<string>;
begin
  Result := SplitAt(StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]), #10);
end;

function IsIdent(const AText: string): Boolean;
var
  Index: Integer;
begin
  for Index := 1 to Length(AText) do
    if not CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit(False);
  Result := True;
end;

function InnermostObject(AObject: TDfmObject; ALine: Integer): TDfmObject;
var
  Child: TDfmObject;
begin
  Result := nil;
  if (ALine < AObject.Range.StartPos.Line) or (ALine > AObject.Range.EndPos.Line) then
    Exit;
  for Child in AObject.Children do
  begin
    Result := InnermostObject(Child, ALine);
    if Result <> nil then
      Exit;
  end;
  Result := AObject;
end;

class function TFormEvents.ContextAt(const AFormText: string; const APosition: TTextPosition;
  out AContext: TFormEventContext): Boolean;
var
  Lines: TArray<string>;
  Before, Name: string;
  Equals: Integer;
  Document: TDfmDocument;
  Obj: TDfmObject;
begin
  AContext := Default(TFormEventContext);
  Result := False;
  Lines := LinesOf(AFormText);
  if (APosition.Line < 0) or (APosition.Line > High(Lines)) then
    Exit;
  Before := Copy(Lines[APosition.Line], 1, APosition.Character);
  Equals := Pos('=', Before);
  if Equals = 0 then
    Exit;
  Name := Trim(Copy(Before, 1, Equals - 1));
  AContext.Prefix := Trim(Copy(Before, Equals + 1, MaxInt));
  if not StartsText('On', Name) or (Length(Name) < 3) or not IsIdent(Name) or not IsIdent(AContext.Prefix) then
    Exit;
  AContext.EventName := Name;
  Document := TDfmParser.Parse(AFormText);
  try
    if Document.Root = nil then
      Exit;
    AContext.FormClass := Document.Root.TypeName;
    Obj := InnermostObject(Document.Root, APosition.Line);
    // Collection-Einträge haben keine bekannte Klasse.
    if (Obj = nil) or (Obj.Kind = TDfmObjectKind.Item) then
      Exit;
    AContext.ComponentName := Obj.Name;
    AContext.ComponentClass := Obj.TypeName;
    Result := (AContext.FormClass <> '') and (AContext.ComponentClass <> '');
  finally
    Document.Free;
  end;
end;

/// <summary>Index des Zeichens hinter dem passenden ";" bzw. vor "of object", ab AStart.</summary>
function DeclarationEnd(const AText: string; AStart: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  Result := AStart;
  while Result <= Length(AText) do
  begin
    case AText[Result] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      ';':
        if Depth = 0 then
          Exit;
    end;
    Inc(Result);
  end;
end;

/// <summary>"procedure(Sender: TObject) of object" → "(Sender: TObject)".</summary>
function TailOfType(const ADeclaration: string): string;
var
  Lower: string;
  Start, Stop: Integer;
begin
  Result := '';
  Lower := LowerCase(ADeclaration);
  Start := Pos('procedure', Lower);
  if Start > 0 then
    Inc(Start, Length('procedure'))
  else
  begin
    Start := Pos('function', Lower);
    if Start = 0 then
      Exit;
    Inc(Start, Length('function'));
  end;
  Stop := DeclarationEnd(ADeclaration, Start);
  Result := Trim(Copy(ADeclaration, Start, Stop - Start));
  if EndsText('of object', Result) then
    Result := Trim(Copy(Result, 1, Length(Result) - Length('of object')));
end;

function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  Line, Index: Integer;
begin
  // 1-basierter Index in AText.
  Line := 0;
  Index := 1;
  while (Line < APosition.Line) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
      Inc(Line)
    else if (AText[Index] = #13) and ((Index = Length(AText)) or (AText[Index + 1] <> #10)) then
      Inc(Line);
    Inc(Index);
  end;
  Result := Index + APosition.Character;
end;

class function TFormEvents.EventTail(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
  const AComponentClass, AEventName: string; out ATail: string): Boolean;
var
  Member: TPublishedMember;
  TypeName, Text: string;
  Location: TSymbolLocation;
  Start: Integer;
begin
  ATail := '';
  TypeName := '';
  if AIndex <> nil then
    for Member in TPublishedMembers.Collect(AIndex, AComponentClass, AReadText) do
      if SameText(Member.Name, AEventName) then
      begin
        TypeName := Member.TypeName;
        Break;
      end;
  if TypeName = '' then
    Exit(False);
  if LastDelimiter('.', TypeName) > 0 then
    TypeName := Copy(TypeName, LastDelimiter('.', TypeName) + 1, MaxInt);
  if Assigned(AReadText) then
    for Location in AIndex.FindSymbols(TypeName) do
      if (Location.Symbol.Container = '') and AReadText(Location.FileName, Text) then
      begin
        Start := OffsetOf(Text, Location.Symbol.SelectionRange.EndPos);
        ATail := TailOfType(Copy(Text, Start, DeclarationEnd(Text, Start) - Start + 1));
        if ATail <> '' then
          Exit(True);
      end;
  if SameText(TypeName, 'TNotifyEvent') then
    ATail := NotifyTail;
  Result := ATail <> '';
end;

/// <summary>Vergleichsschlüssel einer Signatur: Modifizierer und Typ je Parameter, Rückgabetyp;
/// Parameternamen und Standardwerte zählen nicht.</summary>
function SignatureKey(const ATail: string): string;
const
  Modifiers: array[0..3] of string = ('const', 'var', 'out', 'constref');
var
  Tail, Inner, Group, Names, TypeName, Modifier, After: string;
  Close, Colon, Equals, Count, Index: Integer;
begin
  Tail := Trim(ATail);
  Result := '';
  After := Tail;
  if StartsStr('(', Tail) then
  begin
    Close := DeclarationEnd(Tail + ';', 1);
    // DeclarationEnd endet am ";" hinter der Klammer; die schließende Klammer suchen.
    Close := LastDelimiter(')', Copy(Tail, 1, Close - 1));
    Inner := Copy(Tail, 2, Close - 2);
    After := Copy(Tail, Close + 1, MaxInt);
    for Group in SplitAt(Inner, ';') do
    begin
      Colon := Pos(':', Group);
      if Colon = 0 then
      begin
        Names := Trim(Group);
        TypeName := '';
      end
      else
      begin
        Names := Trim(Copy(Group, 1, Colon - 1));
        TypeName := Copy(Group, Colon + 1, MaxInt);
        Equals := Pos('=', TypeName);
        if Equals > 0 then
          TypeName := Copy(TypeName, 1, Equals - 1);
      end;
      if Names = '' then
        Continue;
      Modifier := '';
      for Index := 0 to High(Modifiers) do
        if StartsText(Modifiers[Index] + ' ', Names) then
          Modifier := Modifiers[Index];
      Count := Length(SplitAt(Names, ','));
      for Index := 1 to Count do
        Result := Result + Modifier + ':' + LowerCase(Trim(TypeName)) + ';';
    end;
  end;
  Result := Result + '|' + LowerCase(StringReplace(StringReplace(After, ' ', '', [rfReplaceAll]), ';', '', [rfReplaceAll]));
end;

/// <summary>Deklarationen der Methoden von AFormClass mit ihrer Signatur.</summary>
procedure FormMethods(const AUnitText, AFormClass: string; out ANames, ATails: TArray<string>);
var
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Start: Integer;
  Seen: string;
begin
  ANames := nil;
  ATails := nil;
  UnitIndex := TIndexExtractor.ExtractText(AUnitText, '', nil);
  Seen := ';';
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Method) and SameText(Symbol.Container, AFormClass) and
      (Pos(';' + LowerCase(Symbol.Name) + ';', Seen) = 0) then
    begin
      // Die Deklaration in der Klasse kommt vor dem Rumpf.
      Seen := Seen + LowerCase(Symbol.Name) + ';';
      Start := OffsetOf(AUnitText, Symbol.SelectionRange.EndPos);
      ANames := ANames + [Symbol.Name];
      ATails := ATails + [Trim(Copy(AUnitText, Start, DeclarationEnd(AUnitText, Start) - Start))];
    end;
end;

class function TFormEvents.MatchingMethods(const AUnitText, AFormClass, ATail: string): TArray<string>;
var
  Names, Tails: TArray<string>;
  Key: string;
  Index: Integer;
begin
  Result := nil;
  FormMethods(AUnitText, AFormClass, Names, Tails);
  Key := SignatureKey(ATail);
  for Index := 0 to High(Names) do
    if SignatureKey(Tails[Index]) = Key then
      Result := Result + [Names[Index]];
end;

class function TFormEvents.NewMethodName(const AUnitText, AFormClass, AComponentName, AEventName: string): string;
var
  Names, Tails: TArray<string>;
  Base: string;
  Number: Integer;

  function Taken(const AName: string): Boolean;
  var
    Name: string;
  begin
    for Name in Names do
      if SameText(Name, AName) then
        Exit(True);
    Result := False;
  end;

begin
  FormMethods(AUnitText, AFormClass, Names, Tails);
  Base := AComponentName + Copy(AEventName, 3, MaxInt);
  Result := Base;
  Number := 1;
  while Taken(Result) do
  begin
    Inc(Number);
    Result := Base + IntToStr(Number);
  end;
end;

function LeadingSpaces(const ALine: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
    Inc(Index);
  Result := Copy(ALine, 1, Index - 1);
end;

function StartsWithWord(const ALine: string; const AWords: array of string): Boolean;
var
  Word, Line: string;
begin
  Line := LowerCase(Trim(ALine));
  for Word in AWords do
    if StartsStr(Word, Line) and ((Length(Line) = Length(Word)) or
      not CharInSet(Line[Length(Word) + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) then
      Exit(True);
  Result := False;
end;

class function TFormEvents.CreateHandler(const AUnitText, AFormClass, AMethodName, ATail: string;
  out AEdits: TArray<TRuleEdit>): Boolean;
var
  Lines: TArray<string>;
  UnitIndex: TUnitIndex;
  Symbol, ClassSymbol: TIndexSymbol;
  Found: Boolean;
  Line, InsertLine: Integer;
  Indent, LB, Declaration, NewText: string;
  Tree: TSyntaxTree;
  Action: TCodeAction;
  Edit: TRuleEdit;
begin
  AEdits := nil;
  Result := False;
  Lines := LinesOf(AUnitText);
  UnitIndex := TIndexExtractor.ExtractText(AUnitText, '', nil);
  Found := False;
  ClassSymbol := Default(TIndexSymbol);
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') and SameText(Symbol.Name, AFormClass) then
    begin
      ClassSymbol := Symbol;
      Found := True;
      Break;
    end;
  if not Found then
    Exit;
  // Ende des ersten Abschnitts: erste Sichtbarkeit oder das end der Klasse.
  InsertLine := -1;
  for Line := ClassSymbol.Range.StartPos.Line + 1 to ClassSymbol.Range.EndPos.Line do
    if (Line <= High(Lines)) and StartsWithWord(Lines[Line], ['private', 'protected', 'public', 'published',
      'strict', 'end']) then
    begin
      InsertLine := Line;
      Break;
    end;
  if InsertLine < 0 then
    Exit;
  if (InsertLine - 1 > ClassSymbol.Range.StartPos.Line) and (Trim(Lines[InsertLine - 1]) <> '') then
    Indent := LeadingSpaces(Lines[InsertLine - 1])
  else
    Indent := LeadingSpaces(Lines[InsertLine]) + '  ';
  if Pos(#13#10, AUnitText) > 0 then
    LB := #13#10
  else
    LB := #10;
  if (Pos(')', ATail) > 0) and (Pos(':', Copy(ATail, LastDelimiter(')', ATail) + 1, MaxInt)) > 0) then
    Declaration := 'function '
  else
    Declaration := 'procedure ';
  Declaration := Indent + Declaration + AMethodName + ATail + ';' + LB;
  AEdits := [TRuleEdit.Create(TTextRange.Create(InsertLine, 0, InsertLine, 0), Declaration)];
  // Den Rumpf erzeugt die Klassenvervollständigung im Text mit der neuen Deklaration;
  // ihre Edits liegen hinter der eingefügten Zeile und rücken um eine Zeile zurück.
  NewText := Copy(AUnitText, 1, OffsetOf(AUnitText, TTextPosition.Create(InsertLine, 0)) - 1) + Declaration +
    Copy(AUnitText, OffsetOf(AUnitText, TTextPosition.Create(InsertLine, 0)), MaxInt);
  Tree := TPascalParser.Parse(NewText);
  try
    if TClassCompletion.MissingBodies(Tree, NewText, TTextPosition.Create(InsertLine, Length(Indent) + 1), Action) then
      for Edit in Action.Edits do
        if Edit.Range.StartPos.Line > InsertLine then
          AEdits := AEdits + [TRuleEdit.Create(TTextRange.Create(Edit.Range.StartPos.Line - 1,
            Edit.Range.StartPos.Character, Edit.Range.EndPos.Line - 1, Edit.Range.EndPos.Character), Edit.NewText)];
  finally
    Tree.Free;
  end;
  Result := True;
end;

class function TFormEvents.Items(const AFormFile, AFormText, AUnitText: string; const APosition: TTextPosition;
  const AIndex: ISymbolIndex; const AReadText: TMemberReadText; out AItems: TCompletionItems): Boolean;
var
  Context: TFormEventContext;
  Tail, Name: string;
  Item: TCompletionItem;
begin
  AItems := Default(TCompletionItems);
  if not ContextAt(AFormText, APosition, Context) then
    Exit(False);
  Result := True;
  if not EventTail(AIndex, AReadText, Context.ComponentClass, Context.EventName, Tail) then
    Exit;
  for Name in MatchingMethods(AUnitText, Context.FormClass, Tail) do
  begin
    Item := Default(TCompletionItem);
    Item.Name := Name;
    Item.Detail := 'procedure ' + Name + Tail;
    Item.Kind := KindMethod;
    AItems.Items := AItems.Items + [Item];
  end;
  if AUnitText = '' then
    Exit;
  Name := NewMethodName(AUnitText, Context.FormClass, Context.ComponentName, Context.EventName);
  Item := Default(TCompletionItem);
  Item.Name := Name + ' (neu)';
  Item.InsertText := Name;
  Item.FilterText := Name;
  Item.Detail := Format('Neue Methode %s.%s%s anlegen', [Context.FormClass, Name, Tail]);
  Item.Kind := KindEvent;
  Item.Command := CreateCommand;
  Item.CommandTitle := 'Ereignis-Handler anlegen';
  Item.CommandArguments := [TDocumentUris.FromPath(ChangeFileExt(AFormFile, '.pas')), Context.FormClass, Name, Tail];
  AItems.Items := AItems.Items + [Item];
end;

class function TFormEvents.ApplyEditParams(const AArguments: TJSONArray; const AReadText: TMemberReadText): TJSONObject;
var
  Path, Text, Name: string;
  Names, Tails: TArray<string>;
  Edits: TArray<TRuleEdit>;
  FileEdits: TArray<TFileEdit>;
  Edit: TRuleEdit;
  FileEdit: TFileEdit;
begin
  Result := nil;
  if (AArguments = nil) or (AArguments.Count < 4) or not Assigned(AReadText) then
    Exit;
  Path := TDocumentUris.ToPath(AArguments.Items[0].Value);
  if not AReadText(Path, Text) then
    Exit;
  // Gibt es die Methode schon (zweites Annehmen), bleibt die Unit unverändert.
  FormMethods(Text, AArguments.Items[1].Value, Names, Tails);
  for Name in Names do
    if SameText(Name, AArguments.Items[2].Value) then
      Exit;
  if not CreateHandler(Text, AArguments.Items[1].Value, AArguments.Items[2].Value, AArguments.Items[3].Value, Edits) then
    Exit;
  FileEdits := nil;
  for Edit in Edits do
  begin
    FileEdit.FileName := Path;
    FileEdit.Range := Edit.Range;
    FileEdit.NewText := Edit.NewText;
    FileEdits := FileEdits + [FileEdit];
  end;
  Result := TJSONObject.Create;
  Result.AddPair('label', 'Ereignis-Handler anlegen');
  Result.AddPair('edit', TLspFileOperations.WorkspaceEdit(FileEdits));
end;

end.
