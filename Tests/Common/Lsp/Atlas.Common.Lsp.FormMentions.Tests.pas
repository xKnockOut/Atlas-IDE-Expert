unit Atlas.Common.Lsp.FormMentions.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspFormMentionsTests = class
  public
    [Test]
    procedure MentionsWholeWords;
    [Test]
    procedure LookupReadsDfmAndFmx;
    [Test]
    procedure LookupWithoutReaderIsFalse;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.PromoteVariable,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.FormMentions;

procedure TLspFormMentionsTests.MentionsWholeWords;
begin
  Assert.IsTrue(TLspFormMentions.MentionsWord('object FLabel: TLabel', 'flabel'));
  Assert.IsTrue(TLspFormMentions.MentionsWord('FLabel', 'FLabel'));
  Assert.IsFalse(TLspFormMentions.MentionsWord('object FLabel2: TLabel', 'FLabel'));
  Assert.IsFalse(TLspFormMentions.MentionsWord('object XFLabel: TLabel', 'FLabel'));
end;

function FormReader: TReferenceReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(ExtractFileExt(AFileName), '.fmx');
      if Result then
        AText := 'object Button1: TButton' + sLineBreak + '  OnClick = Button1Click' + sLineBreak + 'end';
    end;
end;

procedure TLspFormMentionsTests.LookupReadsDfmAndFmx;
var
  mInForm: TPromoteInFormFunc;
begin
  mInForm := TLspFormMentions.Lookup('Haupt.pas', FormReader());
  Assert.IsTrue(mInForm('Button1'));
  Assert.IsTrue(mInForm('Button1Click'));
  Assert.IsFalse(mInForm('Button2'));
end;

procedure TLspFormMentionsTests.LookupWithoutReaderIsFalse;
var
  mInForm: TPromoteInFormFunc;
begin
  mInForm := TLspFormMentions.Lookup('Haupt.pas', nil);
  Assert.IsFalse(mInForm('Button1'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspFormMentionsTests);

end.
