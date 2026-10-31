unit Atlas.Common.Lsp.FormMentions;

// Steht ein Name in der Formulardatei zur Unit (.dfm bzw. .fmx daneben)? Das
// fragen „Variable befördern“ (#668) und „Methode ohne Self“ (#686): Ein Feld,
// das das Formular nennt, ist eine Komponente bzw. ein Ereignis und bleibt.
// Eigene Unit, damit „Methode ohne Self“ nicht über „Variable befördern“ die
// Inlay Hints einbindet (Unit-Zyklus, #1450).

interface

uses
  Atlas.Common.Editing.PromoteVariable,
  Atlas.Common.Lsp.References;

type
  TLspFormMentions = class
  public
    /// <summary>Kommt AName als ganzes Wort in AText vor (Groß-/Kleinschreibung egal)?</summary>
    class function MentionsWord(const AText, AName: string): Boolean; static;
    /// <summary>Nennt die .dfm oder .fmx neben AFileName (gelesen über AReadText) einen Namen? Ohne AReadText
    /// immer False.</summary>
    class function Lookup(const AFileName: string; const AReadText: TReferenceReadText): TPromoteInFormFunc; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Chars;

const
  cFormExtensions: array[0..1] of string = ('.dfm', '.fmx');

{ TLspFormMentions }

class function TLspFormMentions.MentionsWord(const AText, AName: string): Boolean;
var
  mStart: Integer;
  mText, mName: string;
begin
  mText := UpperCase(AText);
  mName := UpperCase(AName);
  mStart := PosEx(mName, mText, 1);
  while mStart > 0 do
  begin
    if ((mStart = 1) or not TTextChars.IsIdentChar(mText[mStart - 1])) and
      ((mStart + Length(mName) > Length(mText)) or not TTextChars.IsIdentChar(mText[mStart + Length(mName)])) then
      Exit(True);
    mStart := PosEx(mName, mText, mStart + 1);
  end;
  Result := False;
end;

class function TLspFormMentions.Lookup(const AFileName: string; const AReadText: TReferenceReadText):
  TPromoteInFormFunc;
var
  mFileName: string;
  mReadText: TReferenceReadText;
begin
  mFileName := AFileName;
  mReadText := AReadText;
  Result :=
    function(const AName: string): Boolean
    var
      mExtension, mForm: string;
    begin
      Result := False;
      if not Assigned(mReadText) then
        Exit;
      for mExtension in cFormExtensions do
        if mReadText(ChangeFileExt(mFileName, mExtension), mForm) and MentionsWord(mForm, AName) then
          Exit(True);
    end;
end;

end.
