unit Atlas.Common.Lsp.KeywordReference.Tests;

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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Lsp.KeywordReference;

const
  // Direktiven aus dem Parser (Routinen, Properties, Sichtbarkeit), die ein Hover erklären soll.
  cDirectives: array[0..36] of string = (
    'abstract', 'assembler', 'cdecl', 'deprecated', 'dispid', 'dynamic', 'experimental', 'external',
    'final', 'forward', 'inline', 'library', 'message', 'noreturn', 'overload', 'override', 'pascal',
    'platform', 'register', 'reintroduce', 'safecall', 'static', 'stdcall', 'varargs', 'virtual',
    'winapi', 'delayed', 'absolute', 'implements', 'stored', 'default', 'nodefault', 'index',
    'protected', 'public', 'published', 'automated');

function HoverAt(const AText, AMarker: string; const AVersion: string): string; overload;
var
  mOffset: Integer;
begin
  mOffset := Pos(AMarker, AText);
  Assert.IsTrue(mOffset > 0, AMarker);
  if not TKeywordReference.HoverAt(AText, TTextPosition.Create(0, mOffset), AVersion, Result) then
  begin
    Result := '';
  end;
end;

function HoverAt(const AText, AMarker: string): string; overload;
begin
  Result := HoverAt(AText, AMarker, '37.0');
end;

procedure TKeywordReferenceTests.EveryReservedWordCovered;
var
  mWord: string;
  mInfo: TKeywordInfo;
begin
  for mWord in TPascalLexer.ReservedWordList do
  begin
    Assert.IsTrue(TKeywordReference.Find(mWord, mInfo) or MatchText(mWord, TKeywordReference.cCommonWords), mWord);
  end;
end;

procedure TKeywordReferenceTests.EveryDirectiveCovered;
var
  mWord: string;
  mInfo: TKeywordInfo;
begin
  for mWord in cDirectives do
  begin
    Assert.IsTrue(TKeywordReference.Find(mWord, mInfo), mWord);
  end;
end;

procedure TKeywordReferenceTests.LinkFollowsDelphiVersion;
const
  cSource = 'procedure Paint; reintroduce;';
begin
  Assert.IsTrue(Pos('/RADStudio/Athens/', HoverAt(cSource, 'reintroduce', '23.0')) > 0);
  Assert.IsTrue(Pos('/RADStudio/Florence/', HoverAt(cSource, 'reintroduce', '37.0')) > 0);
  Assert.IsTrue(Pos('**reintroduce** (Direktive)', HoverAt(cSource, 'reintroduce')) > 0);
end;

procedure TKeywordReferenceTests.TwoWordElements;
const
  cSource = 'type T = class strict private class var X: Integer; end;';
begin
  Assert.IsTrue(Pos('**strict private**', HoverAt(cSource, 'strict')) > 0);
  Assert.IsTrue(Pos('**strict private**', HoverAt(cSource, 'private')) > 0);
  Assert.IsTrue(Pos('**class var**', HoverAt(cSource, 'var X')) > 0);
end;

procedure TKeywordReferenceTests.Delphi13Elements;
const
  cSource = 'begin if A is not TFoo then B := if C then 1 else 2; if D not in [1] then end;';
var
  mText: string;
begin
  mText := HoverAt(cSource, 'is not');
  Assert.IsTrue(Pos('**is not**', mText) > 0, mText);
  Assert.IsTrue(Pos('Ab Delphi 13.', mText) > 0, mText);
  Assert.IsFalse(Pos('nicht verfügbar', mText) > 0, mText);
  mText := HoverAt(cSource, 'is not', '23.0');
  Assert.IsTrue(Pos('nicht verfügbar', mText) > 0, mText);
  Assert.IsTrue(Pos('**if … then … else**', HoverAt(cSource, 'if C')) > 0);
  Assert.IsTrue(Pos('**not in**', HoverAt(cSource, 'in [')) > 0);
end;

procedure TKeywordReferenceTests.CommonWordsHaveNoHover;
const
  cSource = 'begin if A then B; end;';
begin
  Assert.AreEqual('', HoverAt(cSource, 'begin'));
  Assert.AreEqual('', HoverAt(cSource, 'if'));
  Assert.AreEqual('', HoverAt(cSource, 'A then'));
end;

procedure TKeywordReferenceTests.TableIsConsistent;
var
  mInfo, mOther: TKeywordInfo;
  mCount: Integer;
begin
  for mInfo in TKeywordReference.All do
  begin
    Assert.AreEqual(LowerCase(mInfo.Name), mInfo.Name);
    Assert.IsTrue((mInfo.Text <> '') and (mInfo.Topic <> '') and (mInfo.Kind <> ''), mInfo.Name);
    Assert.IsFalse(MatchText(mInfo.Name, TKeywordReference.cCommonWords), mInfo.Name);
    mCount := 0;
    for mOther in TKeywordReference.All do
    begin
      if mOther.Name = mInfo.Name then
      begin
        Inc(mCount);
      end;
    end;
    Assert.AreEqual(1, mCount, mInfo.Name);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TKeywordReferenceTests);

end.
