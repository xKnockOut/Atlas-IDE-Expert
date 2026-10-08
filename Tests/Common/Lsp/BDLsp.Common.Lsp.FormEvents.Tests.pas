unit BDLsp.Common.Lsp.FormEvents.Tests;

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.Index.Contract;

type
  [TestFixture]
  TFormEventsTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FindsEventContext;
    [Test]
    procedure IgnoresNonEventProperties;
    [Test]
    procedure ReadsSignatureFromEventType;
    [Test]
    procedure KnowsNotifyEventWithoutDeclaration;
    [Test]
    procedure OffersOnlyMatchingMethods;
    [Test]
    procedure NamesNewMethodAfterComponent;
    [Test]
    procedure CreatesDeclarationAndBody;
    [Test]
    procedure KeepsLineBreaks;
    [Test]
    procedure ItemsContainNewMethodWithCommand;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Index.Extractor,
  BDLsp.Common.Lsp.Completion,
  BDLsp.Common.Lsp.FormEvents;

const
  ControlsFile = 'C:\P\Knoepfe.pas';

  UnitKnoepfe =
    'unit Knoepfe;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TNotifyEvent = procedure(Sender: TObject) of object;'#10 +
    '  TKeyEvent = procedure(Sender: TObject; var Key: Word) of object;'#10 +
    '  TKnopf = class(TObject)'#10 +
    '  published'#10 +
    '    property Caption: string read FCaption write FCaption;'#10 +
    '    property OnClick: TNotifyEvent read FOnClick write FOnClick;'#10 +
    '    property OnKeyDown: TKeyEvent read FOnKeyDown write FOnKeyDown;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  OhneTypFile = 'C:\P\Schalter.pas';

  UnitOhneTyp =
    'unit Schalter;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TSchalter = class(TObject)'#10 +
    '  published'#10 +
    '    property OnClick: TNotifyEvent read FOnClick write FOnClick;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  FormText =
    'object Form1: TForm1'#10 +
    '  Caption = ''Test'''#10 +
    '  object Button1: TKnopf'#10 +
    '    Caption = ''OK'''#10 +
    '    OnClick = '#10 +
    '  end'#10 +
    'end'#10;

  UnitForm =
    'unit Unit1;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TForm1 = class(TForm)'#10 +
    '    Button1: TKnopf;'#10 +
    '    procedure Button1Click(Sender: TObject);'#10 +
    '    procedure Andere(ASender: TObject);'#10 +
    '    procedure Taste(Sender: TObject; var Key: Word);'#10 +
    '  private'#10 +
    '    procedure Intern;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TForm1.Button1Click(Sender: TObject);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TForm1.Andere(ASender: TObject);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TForm1.Taste(Sender: TObject; var Key: Word);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TForm1.Intern;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitLeer =
    'unit Unit1;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TForm1 = class(TForm)'#13#10 +
    '    Button1: TKnopf;'#13#10 +
    '  private'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

function ReadSource(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, ControlsFile) then
    AText := UnitKnoepfe
  else if SameText(AFileName, OhneTypFile) then
    AText := UnitOhneTyp
  else
    Result := False;
end;

function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  Line: Integer;
begin
  Result := 1;
  Line := 0;
  while (Line < APosition.Line) and (Result <= Length(AText)) do
  begin
    if AText[Result] = #10 then
      Inc(Line);
    Inc(Result);
  end;
  Inc(Result, APosition.Character);
end;

function ApplyEdits(const AText: string; const AEdits: TArray<TRuleEdit>): string;
var
  Index: Integer;
begin
  // Von hinten, damit die Positionen der früheren Edits gelten.
  Result := AText;
  for Index := High(AEdits) downto 0 do
    Result := Copy(Result, 1, OffsetOf(Result, AEdits[Index].Range.StartPos) - 1) + AEdits[Index].NewText +
      Copy(Result, OffsetOf(Result, AEdits[Index].Range.EndPos), MaxInt);
end;

{ TFormEventsTests }

procedure TFormEventsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitKnoepfe, ControlsFile, nil));
end;

procedure TFormEventsTests.TearDown;
begin
  FIndex := nil;
end;

procedure TFormEventsTests.FindsEventContext;
var
  Context: TFormEventContext;
begin
  Assert.IsTrue(TFormEvents.ContextAt(FormText, TTextPosition.Create(4, 14), Context));
  Assert.AreEqual('TForm1', Context.FormClass);
  Assert.AreEqual('Button1', Context.ComponentName);
  Assert.AreEqual('TKnopf', Context.ComponentClass);
  Assert.AreEqual('OnClick', Context.EventName);
  Assert.AreEqual('', Context.Prefix);
end;

procedure TFormEventsTests.IgnoresNonEventProperties;
var
  Context: TFormEventContext;
begin
  Assert.IsFalse(TFormEvents.ContextAt(FormText, TTextPosition.Create(3, 14), Context));
end;

procedure TFormEventsTests.ReadsSignatureFromEventType;
var
  Tail: string;
begin
  Assert.IsTrue(TFormEvents.EventTail(FIndex, ReadSource, 'TKnopf', 'OnKeyDown', Tail));
  Assert.AreEqual('(Sender: TObject; var Key: Word)', Tail);
end;

procedure TFormEventsTests.KnowsNotifyEventWithoutDeclaration;
var
  Tail: string;
begin
  // Ohne lesbaren Quelltext des Typs hilft die bekannte Signatur von TNotifyEvent.
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitOhneTyp, OhneTypFile, nil));
  Assert.IsTrue(TFormEvents.EventTail(FIndex, ReadSource, 'TSchalter', 'OnClick', Tail));
  Assert.AreEqual(TFormEvents.NotifyTail, Tail);
end;

procedure TFormEventsTests.OffersOnlyMatchingMethods;
var
  Names: TArray<string>;
begin
  Names := TFormEvents.MatchingMethods(UnitForm, 'TForm1', '(Sender: TObject)');
  Assert.AreEqual(2, Length(Names));
  Assert.AreEqual('Button1Click', Names[0]);
  Assert.AreEqual('Andere', Names[1]);
  Names := TFormEvents.MatchingMethods(UnitForm, 'TForm1', '(Sender: TObject; var Key: Word)');
  Assert.AreEqual(1, Length(Names));
  Assert.AreEqual('Taste', Names[0]);
end;

procedure TFormEventsTests.NamesNewMethodAfterComponent;
begin
  Assert.AreEqual('Button1Click2', TFormEvents.NewMethodName(UnitForm, 'TForm1', 'Button1', 'OnClick'));
  Assert.AreEqual('Button1KeyDown', TFormEvents.NewMethodName(UnitForm, 'TForm1', 'Button1', 'OnKeyDown'));
end;

procedure TFormEventsTests.CreatesDeclarationAndBody;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Assert.IsTrue(TFormEvents.CreateHandler(UnitForm, 'TForm1', 'Button1KeyDown', '(Sender: TObject; var Key: Word)', Edits));
  Assert.AreEqual(2, Length(Edits));
  Text := ApplyEdits(UnitForm, Edits);
  Assert.IsTrue(Pos('    procedure Taste(Sender: TObject; var Key: Word);'#10 +
    '    procedure Button1KeyDown(Sender: TObject; var Key: Word);'#10'  private', Text) > 0, Text);
  Assert.IsTrue(Pos('procedure TForm1.Button1KeyDown(Sender: TObject; var Key: Word);'#10'begin', Text) > 0, Text);
end;

procedure TFormEventsTests.KeepsLineBreaks;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Assert.IsTrue(TFormEvents.CreateHandler(UnitLeer, 'TForm1', 'Button1Click', '(Sender: TObject)', Edits));
  Text := ApplyEdits(UnitLeer, Edits);
  Assert.IsTrue(Pos('    Button1: TKnopf;'#13#10'    procedure Button1Click(Sender: TObject);'#13#10'  private', Text) > 0, Text);
  Assert.IsTrue(Pos('procedure TForm1.Button1Click(Sender: TObject);'#13#10'begin', Text) > 0, Text);
  Assert.AreEqual(0, Pos(#10, StringReplace(Text, #13#10, '', [rfReplaceAll])), 'nur CRLF');
end;

procedure TFormEventsTests.ItemsContainNewMethodWithCommand;
var
  Items: TCompletionItems;
  Last: TCompletionItem;
begin
  Assert.IsTrue(TFormEvents.Items('C:\P\Unit1.dfm', FormText, UnitForm, TTextPosition.Create(4, 14), FIndex,
    ReadSource, Items));
  Assert.AreEqual(3, Length(Items.Items));
  Last := Items.Items[High(Items.Items)];
  Assert.AreEqual('Button1Click2', Last.InsertText);
  Assert.AreEqual(TFormEvents.CreateCommand, Last.Command);
  Assert.AreEqual(4, Length(Last.CommandArguments));
  Assert.AreEqual('(Sender: TObject)', Last.CommandArguments[3]);
end;

initialization
  TDUnitX.RegisterTestFixture(TFormEventsTests);

end.
