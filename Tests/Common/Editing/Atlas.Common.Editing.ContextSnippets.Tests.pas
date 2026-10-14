unit Atlas.Common.Editing.ContextSnippets.Tests;

// Tests für die kontextabhängigen Code-Vorlagen der Vervollständigung (#51):
// prop, changed, create und free, Klartext ohne snippetSupport und derselbe
// Setter wie bei /prop.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TContextSnippetsTests = class
  public
    [Test]
    procedure PropForFieldsWithoutProperty;
    [Test]
    procedure ChangedInEmptySetter;
    [Test]
    procedure CreateObjectFieldsInConstructor;
    [Test]
    procedure FreeCreatedFieldsInDestructor;
    [Test]
    procedure NothingBesideOtherCode;
    [Test]
    procedure PlainTextAndEscape;
    [Test]
    procedure PropCommandWritesSameSetter;
  end;

  [TestFixture]
  TContextSnippetCompletionTests = class
  public
    [Test]
    procedure SnippetOnlyWithClientSupport;
    [Test]
    procedure ReadsSnippetSupport;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.ContextSnippets,
  Atlas.Common.Lsp.Completion;

const
  Anzeige =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAnzeige = class(TCustomControl)'#10 +
    '  private'#10 +
    '    FFarbe: TColor;'#10 +
    '    FRand: Integer;'#10 +
    '  published'#10 +
    '    property Rand: Integer read FRand write FRand;'#10 +
    '    %s'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  Setter =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAnzeige = class(TCustomControl)'#10 +
    '  private'#10 +
    '    FFarbe: TColor;'#10 +
    '    procedure SetFarbe(const AFarbe: TColor);'#10 +
    '  published'#10 +
    '    property Farbe: TColor read FFarbe write SetFarbe;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TAnzeige.SetFarbe(const AFarbe: TColor);'#10 +
    'begin'#10 +
    '  %s'#10 +
    'end;'#10 +
    'end.';

  Kunden =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TTimer = class(TComponent)'#10 +
    '  end;'#10 +
    '  TListe = class'#10 +
    '  end;'#10 +
    '  TKunden = class(TComponent)'#10 +
    '  private'#10 +
    '    FListe: TListe;'#10 +
    '    FTimer: TTimer;'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    constructor Create(AOwner: TComponent); override;'#10 +
    '    destructor Destroy; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TKunden.Create(AOwner: TComponent);'#10 +
    'begin'#10 +
    '  %s'#10 +
    'end;'#10 +
    'destructor TKunden.Destroy;'#10 +
    'begin'#10 +
    '  %s'#10 +
    '  inherited;'#10 +
    'end;'#10 +
    'end.';

/// <summary>Kontext für den Cursor hinter "|" in AText; AText ohne "|".</summary>
function ContextAt(var AText: string; out ACharacter: Integer): TSlashContext;
var
  Lines: TArray<string>;
  Index, Bar: Integer;
begin
  Result := Default(TSlashContext);
  Lines := AText.Split([#10]);
  for Index := 0 to High(Lines) do
  begin
    Bar := Pos('|', Lines[Index]);
    if Bar > 0 then
    begin
      Delete(Lines[Index], Bar, 1);
      Result.Line := Index;
      Result.LineText := Lines[Index];
      ACharacter := Bar - 1;
    end;
  end;
  AText := string.Join(#10, Lines);
  Result.Text := AText;
end;

function SnippetsAt(const ACode: string): TArray<TContextSnippet>;
var
  Text: string;
  Character: Integer;
begin
  Text := ACode;
  Result := TContextSnippets.At(ContextAt(Text, Character), Character);
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function Apply(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Offsets: TArray<Integer>;
  Index, Start, Stop: Integer;
begin
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in AEdits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

{ TContextSnippetsTests }

procedure TContextSnippetsTests.PropForFieldsWithoutProperty;
var
  Snippets: TArray<TContextSnippet>;
  Text, Code: string;
  Character: Integer;
  Context: TSlashContext;
  Edits: TArray<TRuleEdit>;
begin
  Snippets := SnippetsAt(Format(Anzeige, ['pro|']));
  // FRand hat schon eine Property.
  Assert.AreEqual(1, Integer(Length(Snippets)));
  Assert.AreEqual('prop', Snippets[0].Prefix);
  Assert.AreEqual('prop Farbe', Snippets[0].Name);
  Assert.AreEqual('property ${1:Farbe}: TColor read FFarbe write SetFarbe;$0', Snippets[0].Text);
  // Eingesetzt mit den Vorgaben: Deklaration im private-Abschnitt, Rumpf mit Prüfung und Invalidate.
  Code := Format(Anzeige, ['pro|']);
  Context := ContextAt(Code, Character);
  Edits := Snippets[0].AdditionalEdits + [TRuleEdit.Create(TTextRange.Create(Context.Line, 4, Context.Line,
    Character), TContextSnippets.ToPlain(Snippets[0].Text))];
  Text := Apply(Code, Edits);
  Assert.Contains(Text, '    property Farbe: TColor read FFarbe write SetFarbe;'#10'  private'#10 +
    '    procedure SetFarbe(const Value: TColor);'#10'  end;');
  Assert.Contains(Text, 'procedure TAnzeige.SetFarbe(const Value: TColor);'#10'begin'#10 +
    '  if FFarbe <> Value then'#10'  begin'#10'    FFarbe := Value;'#10'    Invalidate;'#10'  end;'#10'end;');
  Assert.IsTrue(Parses(Text), Text);
  // Ohne Feld ohne Property nichts.
  Assert.AreEqual(0, Integer(Length(SnippetsAt(StringReplace(Format(Anzeige, ['|']), '    FFarbe: TColor;'#10, '',
    [])))));
end;

procedure TContextSnippetsTests.ChangedInEmptySetter;
var
  Snippets: TArray<TContextSnippet>;
begin
  Snippets := SnippetsAt(Format(Setter, ['ch|']));
  Assert.AreEqual(1, Integer(Length(Snippets)));
  Assert.AreEqual('changed', Snippets[0].Prefix);
  Assert.AreEqual('if FFarbe <> AFarbe then'#10'begin'#10'  FFarbe := AFarbe;'#10'  ${1:Invalidate};'#10'end;$0',
    Snippets[0].Text);
  Assert.AreEqual(0, Integer(Length(Snippets[0].AdditionalEdits)));
  // Weist der Rumpf das Feld schon zu, gibt es nichts mehr.
  Assert.AreEqual(0, Integer(Length(SnippetsAt(StringReplace(Format(Setter, ['|']), 'begin'#10,
    'begin'#10'  FFarbe := AFarbe;'#10, [])))));
end;

procedure TContextSnippetsTests.CreateObjectFieldsInConstructor;
var
  Snippets: TArray<TContextSnippet>;
begin
  Snippets := SnippetsAt(Format(Kunden, ['cr|', '']));
  Assert.AreEqual(1, Integer(Length(Snippets)));
  Assert.AreEqual('create', Snippets[0].Prefix);
  // FName ist kein Objekt; TTimer ist eine Komponente und bekommt Self als Owner.
  Assert.AreEqual('inherited;'#10'FListe := ${1:TListe}.Create;'#10'FTimer := ${2:TTimer}.Create(Self);$0',
    Snippets[0].Text);
  // Schon erzeugte Felder fehlen, inherited steht schon da.
  Snippets := SnippetsAt(StringReplace(Format(Kunden, ['|', '']), 'begin'#10'  |',
    'begin'#10'  inherited;'#10'  FListe := TListe.Create;'#10'  |', []));
  Assert.AreEqual(1, Integer(Length(Snippets)));
  Assert.AreEqual('FTimer := ${1:TTimer}.Create(Self);$0', Snippets[0].Text);
end;

procedure TContextSnippetsTests.FreeCreatedFieldsInDestructor;
var
  Snippets: TArray<TContextSnippet>;
  Code: string;
begin
  Code := Format(Kunden, ['inherited;'#10'  FListe := TListe.Create;'#10'  FTimer := TTimer.Create(Self);', 'fr|']);
  Snippets := SnippetsAt(Code);
  Assert.AreEqual(1, Integer(Length(Snippets)));
  Assert.AreEqual('free', Snippets[0].Prefix);
  // Umgekehrte Reihenfolge wie /dtor; inherited steht schon im Rumpf.
  Assert.AreEqual('FreeAndNil(FTimer);'#10'FreeAndNil(FListe);$0', Snippets[0].Text);
  // Ohne inherited kommt es dazu; schon freigegebene Felder fehlen.
  Code := StringReplace(Code, '  inherited;'#10'end;'#10'end.', '  FTimer.Free;'#10'end;'#10'end.', []);
  Snippets := SnippetsAt(Code);
  Assert.AreEqual(1, Integer(Length(Snippets)));
  Assert.AreEqual('FreeAndNil(FListe);$0'#10'inherited;', Snippets[0].Text);
end;

procedure TContextSnippetsTests.NothingBesideOtherCode;
begin
  // Weiterer Code vor oder hinter dem Cursor.
  Assert.AreEqual(0, Integer(Length(SnippetsAt(Format(Setter, ['X := ch|'])))));
  Assert.AreEqual(0, Integer(Length(SnippetsAt(Format(Setter, ['ch| X;'])))));
  // Außerhalb einer Klasse.
  Assert.AreEqual(0, Integer(Length(SnippetsAt('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10 +
    'begin'#10'  fr|'#10'end;'#10'end.'))));
end;

procedure TContextSnippetsTests.PlainTextAndEscape;
begin
  Assert.AreEqual('property Farbe: TColor;', TContextSnippets.ToPlain('property ${1:Farbe}: ${2:TColor};$0'));
  Assert.AreEqual('X := $FF; a}b\c', TContextSnippets.ToPlain('X := \$FF; a\}b\\c'));
  Assert.AreEqual('Wert ja $FF', TContextSnippets.ToPlain('${1:Wert} ${2|ja,nein|} ${TM_SELECTED_TEXT}$FF${3}'));
  Assert.AreEqual('Liste.Free', TContextSnippets.ToPlain('${1:${2:Liste}.Free}'));
  Assert.AreEqual('a\$b\}c\\', TContextSnippets.Escape('a$b}c\'));
  Assert.AreEqual('$FF', TContextSnippets.ToPlain(TContextSnippets.Escape('$FF')));
end;

procedure TContextSnippetsTests.PropCommandWritesSameSetter;
var
  Code, Text: string;
  Edits: TArray<TRuleEdit>;
begin
  // /prop und die Vorlage nutzen denselben Erzeuger (#51 „Abgrenzung zu Code-Aktionen“).
  Code := Format(Anzeige, ['/prop Breite: Integer']);
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(Code, TTextPosition.Create(10, 0), nil, nil, Edits));
  Text := Apply(Code, Edits);
  Assert.Contains(Text, 'procedure TAnzeige.SetBreite(const Value: Integer);'#10 +
    TSetterGenerator.Body('FBreite', 'Value', 'Invalidate', #10));
  Assert.IsTrue(Parses(Text), Text);
end;

{ TContextSnippetCompletionTests }

procedure TContextSnippetCompletionTests.SnippetOnlyWithClientSupport;
var
  Code: string;
  Character: Integer;
  Context: TSlashContext;
  Items: TArray<TCompletionItem>;
  Json: TJSONArray;
begin
  Code := Format(Setter, ['ch|']);
  Context := ContextAt(Code, Character);
  // Ohne snippetSupport: Klartext ohne "${", kein insertTextFormat.
  Items := TLspCompletion.ContextItems(nil, nil, Code, TTextPosition.Create(Context.Line, Character),
    TCompletionMatching.Fuzzy, False);
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.IsFalse(Items[0].Snippet);
  Assert.AreEqual(0, Pos('${', Items[0].TextEdit.NewText));
  Assert.AreEqual('if FFarbe <> AFarbe then'#10'begin'#10'  FFarbe := AFarbe;'#10'  Invalidate;'#10'end;',
    Items[0].TextEdit.NewText);
  Assert.AreEqual(2, Items[0].TextEdit.Range.StartPos.Character);
  Assert.AreEqual('snippet', Items[0].Action);
  Json := TLspCompletion.ToJson(Items, 0);
  try
    Assert.IsNull(TJSONObject(Json.Items[0]).GetValue('insertTextFormat'));
    Assert.AreEqual(0, Pos('${', Json.ToJSON));
  finally
    Json.Free;
  end;
  // Mit snippetSupport: Snippet mit Platzhalter.
  Items := TLspCompletion.ContextItems(nil, nil, Code, TTextPosition.Create(Context.Line, Character),
    TCompletionMatching.Fuzzy, True);
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.IsTrue(Items[0].Snippet);
  Assert.Contains(Items[0].TextEdit.NewText, '${1:Invalidate}');
  Json := TLspCompletion.ToJson(Items, 0);
  try
    Assert.AreEqual(2, TJSONObject(Json.Items[0]).GetValue<Integer>('insertTextFormat'));
  finally
    Json.Free;
  end;
  // Passt das Wort nicht, kommt nichts.
  Code := Format(Setter, ['xyz|']);
  Context := ContextAt(Code, Character);
  Assert.AreEqual(0, Integer(Length(TLspCompletion.ContextItems(nil, nil, Code, TTextPosition.Create(Context.Line,
    Character), TCompletionMatching.Prefix, True))));
end;

procedure TContextSnippetCompletionTests.ReadsSnippetSupport;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.ParseJSONValue(
    '{"capabilities":{"textDocument":{"completion":{"completionItem":{"snippetSupport":true}}}}}') as TJSONObject;
  try
    Assert.IsTrue(TLspCompletion.ClientSupportsSnippets(Params));
  finally
    Params.Free;
  end;
  Params := TJSONObject.ParseJSONValue('{"capabilities":{}}') as TJSONObject;
  try
    Assert.IsFalse(TLspCompletion.ClientSupportsSnippets(Params));
  finally
    Params.Free;
  end;
  Assert.IsFalse(TLspCompletion.ClientSupportsSnippets(nil));
end;

end.
