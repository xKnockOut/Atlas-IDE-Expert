unit Atlas.Common.Editing.FormMentions.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormMentionsTests = class
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
  Atlas.Common.Editing.FormMentions,
  Atlas.Common.Semantics.References;

{ TFormMentionsTests }

procedure TFormMentionsTests.MentionsWholeWords;
begin
  Assert.IsTrue(TFormMentions.MentionsWord('object FLabel: TLabel', 'flabel'));
  Assert.IsTrue(TFormMentions.MentionsWord('FLabel', 'FLabel'));
  Assert.IsFalse(TFormMentions.MentionsWord('object FLabel2: TLabel', 'FLabel'));
  Assert.IsFalse(TFormMentions.MentionsWord('object XFLabel: TLabel', 'FLabel'));
end;

function FormReader: TReferenceReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(ExtractFileExt(AFileName), '.fmx');
      if Result then
      begin
        AText := 'object Button1: TButton' + sLineBreak + '  OnClick = Button1Click' + sLineBreak + 'end';
      end;
    end;
end;

procedure TFormMentionsTests.LookupReadsDfmAndFmx;
var
  mInForm: TPromoteInFormFunc;
begin
  mInForm := TFormMentions.Lookup('Haupt.pas', FormReader());
  Assert.IsTrue(mInForm('Button1'));
  Assert.IsTrue(mInForm('Button1Click'));
  Assert.IsFalse(mInForm('Button2'));
end;

procedure TFormMentionsTests.LookupWithoutReaderIsFalse;
var
  mInForm: TPromoteInFormFunc;
begin
  mInForm := TFormMentions.Lookup('Haupt.pas', nil);
  Assert.IsFalse(mInForm('Button1'));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormMentionsTests);

end.
