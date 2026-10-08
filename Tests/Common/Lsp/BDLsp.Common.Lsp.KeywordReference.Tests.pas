unit BDLsp.Common.Lsp.KeywordReference.Tests;

// Tests für den Hover über Schlüsselwörtern und Direktiven (#187).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TKeywordReferenceTests = class
  public
    [Test]
    procedure EveryReservedWordCovered;
    [Test]
    procedure EveryDirectiveCovered;
    [Test]
    procedure LinkFollowsDelphiVersion;
    [Test]
    procedure TwoWordElements;
    [Test]
    procedure Delphi13Elements;
    [Test]
    procedure CommonWordsHaveNoHover;
    [Test]
    procedure TableIsConsistent;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Lexer,
  BDLsp.Common.Lsp.KeywordReference;

const
  // Direktiven aus dem Parser (Routinen, Properties, Sichtbarkeit), die ein Hover erklären soll.
  Directives: array[0..36] of string = (
    'abstract', 'assembler', 'cdecl', 'deprecated', 'dispid', 'dynamic', 'experimental', 'external',
    'final', 'forward', 'inline', 'library', 'message', 'noreturn', 'overload', 'override', 'pascal',
    'platform', 'register', 'reintroduce', 'safecall', 'static', 'stdcall', 'varargs', 'virtual',
    'winapi', 'delayed', 'absolute', 'implements', 'stored', 'default', 'nodefault', 'index',
    'protected', 'public', 'published', 'automated');

function HoverAt(const AText, AMarker: string; const AVersion: string = '37.0'): string;
var
  Offset: Integer;
begin
  Offset := Pos(AMarker, AText);
  Assert.IsTrue(Offset > 0, AMarker);
  if not TKeywordReference.HoverAt(AText, TTextPosition.Create(0, Offset), AVersion, Result) then
    Result := '';
end;

procedure TKeywordReferenceTests.EveryReservedWordCovered;
var
  Word: string;
  Info: TKeywordInfo;
begin
  for Word in TPascalLexer.ReservedWordList do
    Assert.IsTrue(TKeywordReference.Find(Word, Info) or MatchText(Word, TKeywordReference.CommonWords), Word);
end;

procedure TKeywordReferenceTests.EveryDirectiveCovered;
var
  Word: string;
  Info: TKeywordInfo;
begin
  for Word in Directives do
    Assert.IsTrue(TKeywordReference.Find(Word, Info), Word);
end;

procedure TKeywordReferenceTests.LinkFollowsDelphiVersion;
const
  Source = 'procedure Paint; reintroduce;';
begin
  Assert.IsTrue(Pos('/RADStudio/Athens/', HoverAt(Source, 'reintroduce', '23.0')) > 0);
  Assert.IsTrue(Pos('/RADStudio/Florence/', HoverAt(Source, 'reintroduce', '37.0')) > 0);
  Assert.IsTrue(Pos('**reintroduce** (Direktive)', HoverAt(Source, 'reintroduce')) > 0);
end;

procedure TKeywordReferenceTests.TwoWordElements;
const
  Source = 'type T = class strict private class var X: Integer; end;';
begin
  Assert.IsTrue(Pos('**strict private**', HoverAt(Source, 'strict')) > 0);
  Assert.IsTrue(Pos('**strict private**', HoverAt(Source, 'private')) > 0);
  Assert.IsTrue(Pos('**class var**', HoverAt(Source, 'var X')) > 0);
end;

procedure TKeywordReferenceTests.Delphi13Elements;
const
  Source = 'begin if A is not TFoo then B := if C then 1 else 2; if D not in [1] then end;';
var
  Text: string;
begin
  Text := HoverAt(Source, 'is not');
  Assert.IsTrue(Pos('**is not**', Text) > 0, Text);
  Assert.IsTrue(Pos('Ab Delphi 13.', Text) > 0, Text);
  Assert.IsFalse(Pos('nicht verfügbar', Text) > 0, Text);
  Text := HoverAt(Source, 'is not', '23.0');
  Assert.IsTrue(Pos('nicht verfügbar', Text) > 0, Text);
  Assert.IsTrue(Pos('**if … then … else**', HoverAt(Source, 'if C')) > 0);
  Assert.IsTrue(Pos('**not in**', HoverAt(Source, 'in [')) > 0);
end;

procedure TKeywordReferenceTests.CommonWordsHaveNoHover;
const
  Source = 'begin if A then B; end;';
begin
  Assert.AreEqual('', HoverAt(Source, 'begin'));
  Assert.AreEqual('', HoverAt(Source, 'if'));
  Assert.AreEqual('', HoverAt(Source, 'A then'));
end;

procedure TKeywordReferenceTests.TableIsConsistent;
var
  Info, Other: TKeywordInfo;
  Count: Integer;
begin
  for Info in TKeywordReference.All do
  begin
    Assert.AreEqual(LowerCase(Info.Name), Info.Name);
    Assert.IsTrue((Info.Text <> '') and (Info.Topic <> '') and (Info.Kind <> ''), Info.Name);
    Assert.IsFalse(MatchText(Info.Name, TKeywordReference.CommonWords), Info.Name);
    Count := 0;
    for Other in TKeywordReference.All do
      if Other.Name = Info.Name then
        Inc(Count);
    Assert.AreEqual(1, Count, Info.Name);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TKeywordReferenceTests);

end.
