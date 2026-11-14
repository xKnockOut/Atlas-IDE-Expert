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
  Atlas.Common.Lsp.Completion.Lists,
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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.ContextSnippets,
  Atlas.Common.Lsp.Completion;

const
  cAnzeige =
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

  cSetter =
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

  cKunden =
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
  mLines: TArray<string>;
  mIndex, mBar: Integer;
begin
  Result := Default(TSlashContext);
  mLines := AText.Split([#10]);
  for mIndex := 0 to High(mLines) do
  begin
    mBar := Pos('|', mLines[mIndex]);
    if mBar > 0 then
    begin
      Delete(mLines[mIndex], mBar, 1);
      Result.Line := mIndex;
      Result.LineText := mLines[mIndex];
      ACharacter := mBar - 1;
    end;
  end;
  AText := string.Join(#10, mLines);
  Result.Text := AText;
end;

function SnippetsAt(const ACode: string): TArray<TContextSnippet>;
var
  mText: string;
  mCharacter: Integer;
begin
  mText := ACode;
  Result := TContextSnippets.At(ContextAt(mText, mCharacter), mCharacter);
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function Apply(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mOffsets: TArray<Integer>;
  mIndex, mStart, mStop: Integer;
begin
  mLines := AText.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for mEdit in AEdits do
  begin
    mStart := mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character;
    mStop := mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character;
    Result := Copy(Result, 1, mStart) + mEdit.NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

{ TContextSnippetsTests }

procedure TContextSnippetsTests.PropForFieldsWithoutProperty;
var
  mSnippets: TArray<TContextSnippet>;
  mText, mCode: string;
  mCharacter: Integer;
  mContext: TSlashContext;
  mEdits: TArray<TRuleEdit>;
begin
  mSnippets := SnippetsAt(Format(cAnzeige, ['pro|']));
  // FRand hat schon eine Property.
  Assert.AreEqual(1, Integer(Length(mSnippets)));
  Assert.AreEqual('prop', mSnippets[0].Prefix);
  Assert.AreEqual('prop Farbe', mSnippets[0].Name);
  Assert.AreEqual('property ${1:Farbe}: TColor read FFarbe write SetFarbe;$0', mSnippets[0].Text);
  // Eingesetzt mit den Vorgaben: Deklaration im private-Abschnitt, Rumpf mit Prüfung und Invalidate.
  mCode := Format(cAnzeige, ['pro|']);
  mContext := ContextAt(mCode, mCharacter);
  mEdits := mSnippets[0].AdditionalEdits + [TRuleEdit.Create(TTextRange.Create(mContext.Line, 4, mContext.Line,
    mCharacter), TContextSnippets.ToPlain(mSnippets[0].Text))];
  mText := Apply(mCode, mEdits);
  Assert.Contains(mText, '    property Farbe: TColor read FFarbe write SetFarbe;'#10'  private'#10 +
    '    procedure SetFarbe(const Value: TColor);'#10'  end;');
  Assert.Contains(mText, 'procedure TAnzeige.SetFarbe(const Value: TColor);'#10'begin'#10 +
    '  if FFarbe <> Value then'#10'  begin'#10'    FFarbe := Value;'#10'    Invalidate;'#10'  end;'#10'end;');
  Assert.IsTrue(Parses(mText), mText);
  // Ohne Feld ohne Property nichts.
  Assert.AreEqual(0, Integer(Length(SnippetsAt(StringReplace(Format(cAnzeige, ['|']), '    FFarbe: TColor;'#10, '',
    [])))));
end;

procedure TContextSnippetsTests.ChangedInEmptySetter;
var
  mSnippets: TArray<TContextSnippet>;
begin
  mSnippets := SnippetsAt(Format(cSetter, ['ch|']));
  Assert.AreEqual(1, Integer(Length(mSnippets)));
  Assert.AreEqual('changed', mSnippets[0].Prefix);
  Assert.AreEqual('if FFarbe <> AFarbe then'#10'begin'#10'  FFarbe := AFarbe;'#10'  ${1:Invalidate};'#10'end;$0',
    mSnippets[0].Text);
  Assert.AreEqual(0, Integer(Length(mSnippets[0].AdditionalEdits)));
  // Weist der Rumpf das Feld schon zu, gibt es nichts mehr.
  Assert.AreEqual(0, Integer(Length(SnippetsAt(StringReplace(Format(cSetter, ['|']), 'begin'#10,
    'begin'#10'  FFarbe := AFarbe;'#10, [])))));
end;

procedure TContextSnippetsTests.CreateObjectFieldsInConstructor;
var
  mSnippets: TArray<TContextSnippet>;
begin
  mSnippets := SnippetsAt(Format(cKunden, ['cr|', '']));
  Assert.AreEqual(1, Integer(Length(mSnippets)));
  Assert.AreEqual('create', mSnippets[0].Prefix);
  // FName ist kein Objekt; TTimer ist eine Komponente und bekommt Self als Owner.
  Assert.AreEqual('inherited;'#10'FListe := ${1:TListe}.Create;'#10'FTimer := ${2:TTimer}.Create(Self);$0',
    mSnippets[0].Text);
  // Schon erzeugte Felder fehlen, inherited steht schon da.
  mSnippets := SnippetsAt(StringReplace(Format(cKunden, ['|', '']), 'begin'#10'  |',
    'begin'#10'  inherited;'#10'  FListe := TListe.Create;'#10'  |', []));
  Assert.AreEqual(1, Integer(Length(mSnippets)));
  Assert.AreEqual('FTimer := ${1:TTimer}.Create(Self);$0', mSnippets[0].Text);
end;

procedure TContextSnippetsTests.FreeCreatedFieldsInDestructor;
var
  mSnippets: TArray<TContextSnippet>;
  mCode: string;
begin
  mCode := Format(cKunden, ['inherited;'#10'  FListe := TListe.Create;'#10'  FTimer := TTimer.Create(Self);', 'fr|']);
  mSnippets := SnippetsAt(mCode);
  Assert.AreEqual(1, Integer(Length(mSnippets)));
  Assert.AreEqual('free', mSnippets[0].Prefix);
  // Umgekehrte Reihenfolge wie /dtor; inherited steht schon im Rumpf.
  Assert.AreEqual('FreeAndNil(FTimer);'#10'FreeAndNil(FListe);$0', mSnippets[0].Text);
  // Ohne inherited kommt es dazu; schon freigegebene Felder fehlen.
  mCode := StringReplace(mCode, '  inherited;'#10'end;'#10'end.', '  FTimer.Free;'#10'end;'#10'end.', []);
  mSnippets := SnippetsAt(mCode);
  Assert.AreEqual(1, Integer(Length(mSnippets)));
  Assert.AreEqual('FreeAndNil(FListe);$0'#10'inherited;', mSnippets[0].Text);
end;

procedure TContextSnippetsTests.NothingBesideOtherCode;
begin
  // Weiterer Code vor oder hinter dem Cursor.
  Assert.AreEqual(0, Integer(Length(SnippetsAt(Format(cSetter, ['X := ch|'])))));
  Assert.AreEqual(0, Integer(Length(SnippetsAt(Format(cSetter, ['ch| X;'])))));
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
  mCode, mText: string;
  mEdits: TArray<TRuleEdit>;
begin
  // /prop und die Vorlage nutzen denselben Erzeuger (#51 „Abgrenzung zu Code-Aktionen“).
  mCode := Format(cAnzeige, ['/prop Breite: Integer']);
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(mCode, TTextPosition.Create(10, 0), nil, nil, mEdits));
  mText := Apply(mCode, mEdits);
  Assert.Contains(mText, 'procedure TAnzeige.SetBreite(const Value: Integer);'#10 +
    TSetterGenerator.Body('FBreite', 'Value', 'Invalidate', #10));
  Assert.IsTrue(Parses(mText), mText);
end;

{ TContextSnippetCompletionTests }

procedure TContextSnippetCompletionTests.SnippetOnlyWithClientSupport;
var
  mCode: string;
  mCharacter: Integer;
  mContext: TSlashContext;
  mItems: TArray<TCompletionItem>;
  mJson: TJSONArray;
begin
  mCode := Format(cSetter, ['ch|']);
  mContext := ContextAt(mCode, mCharacter);
  // Ohne snippetSupport: Klartext ohne "${", kein insertTextFormat.
  mItems := TCompletionLists.ContextItems(nil, nil, mCode, TTextPosition.Create(mContext.Line, mCharacter),
    TCompletionMatching.Fuzzy, False);
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.IsFalse(mItems[0].Snippet);
  Assert.AreEqual(0, Pos('${', mItems[0].TextEdit.NewText));
  Assert.AreEqual('if FFarbe <> AFarbe then'#10'begin'#10'  FFarbe := AFarbe;'#10'  Invalidate;'#10'end;',
    mItems[0].TextEdit.NewText);
  Assert.AreEqual(2, mItems[0].TextEdit.Range.StartPos.Character);
  Assert.AreEqual('snippet', mItems[0].Action);
  mJson := TLspCompletion.ToJson(mItems, 0);
  try
    Assert.IsNull(TJSONObject(mJson.Items[0]).GetValue('insertTextFormat'));
    Assert.AreEqual(0, Pos('${', mJson.ToJSON));
  finally
    mJson.Free;
  end;
  // Mit snippetSupport: Snippet mit Platzhalter.
  mItems := TCompletionLists.ContextItems(nil, nil, mCode, TTextPosition.Create(mContext.Line, mCharacter),
    TCompletionMatching.Fuzzy, True);
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.IsTrue(mItems[0].Snippet);
  Assert.Contains(mItems[0].TextEdit.NewText, '${1:Invalidate}');
  mJson := TLspCompletion.ToJson(mItems, 0);
  try
    Assert.AreEqual(2, TJSONObject(mJson.Items[0]).GetValue<Integer>('insertTextFormat'));
  finally
    mJson.Free;
  end;
  // Passt das Wort nicht, kommt nichts.
  mCode := Format(cSetter, ['xyz|']);
  mContext := ContextAt(mCode, mCharacter);
  Assert.AreEqual(0, Integer(Length(TCompletionLists.ContextItems(nil, nil, mCode, TTextPosition.Create(mContext.Line,
    mCharacter), TCompletionMatching.Prefix, True))));
end;

procedure TContextSnippetCompletionTests.ReadsSnippetSupport;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.ParseJSONValue(
    '{"capabilities":{"textDocument":{"completion":{"completionItem":{"snippetSupport":true}}}}}') as TJSONObject;
  try
    Assert.IsTrue(TLspCompletion.ClientSupportsSnippets(mParams));
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"capabilities":{}}') as TJSONObject;
  try
    Assert.IsFalse(TLspCompletion.ClientSupportsSnippets(mParams));
  finally
    mParams.Free;
  end;
  Assert.IsFalse(TLspCompletion.ClientSupportsSnippets(nil));
end;

end.
