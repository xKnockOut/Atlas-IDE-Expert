unit Atlas.Common.Editing.UnitTemplates;

// Gerüste für neue Formulare, Frames, Datenmodule und Komponenten (#299):
// Unit-Text, DFM und die Einträge in .dpr und .dproj, wie die IDE sie anlegt.
// Reine Textfunktionen; Anlegen der Dateien und Öffnen übernimmt der Aufrufer.

interface

uses
  Atlas.Common.Documents.Contract;

type
  TFormKind = (Form, Frame, DataModule);

  /// <summary>Was die Unit eines neuen Formulars enthält.</summary>
  TFormUnitSpec = record
    UnitName: string;
    ClassName: string;
    /// <summary>Vorfahr; leer = Standard der Art.</summary>
    Ancestor: string;
    /// <summary>Unit des Vorfahren; kommt zusätzlich ins uses, wenn nicht leer.</summary>
    AncestorUnit: string;
    Kind: TFormKind;
    /// <summary>Globale Variable für die Instanz anlegen.</summary>
    GlobalVariable: Boolean;
    /// <summary>Formular ohne eigenen Vorfahren und ohne globale Variable.</summary>
    class function Create(const AUnitName, AClassName: string; AKind: TFormKind): TFormUnitSpec; static;
  end;

  TUnitTemplates = class
  public
    /// <summary>Name der Instanz bzw. Datei zum Klassennamen: TKundenForm wird KundenForm.</summary>
    class function InstanceName(const AClassName: string): string; static;
    /// <summary>Standard-Vorfahr der Art: TForm, TFrame, TDataModule.</summary>
    class function DefaultAncestor(AKind: TFormKind): string; static;
    /// <summary>Unit zu einem Formular nach ASpec.</summary>
    class function FormUnit(const ASpec: TFormUnitSpec; const ALineBreak: string): string; static;
    /// <summary>DFM zum Formular; AInherited für geerbte Formulare ("inherited" statt "object").</summary>
    class function FormDfm(const AClassName: string; AKind: TFormKind; AInherited: Boolean;
      const ALineBreak: string): string; static;
    /// <summary>Unit einer neuen Komponente mit published-Abschnitt und Register.</summary>
    class function ComponentUnit(const AUnitName, AClassName, AAncestor, AAncestorUnit, APalette: string;
      const ALineBreak: string): string; static;
    /// <summary>Edits für die .dpr: Eintrag im uses mit {Kommentar} und bei Formularen und
    /// Datenmodulen Application.CreateForm vor Application.Run. False ohne uses.</summary>
    class function ProgramEdits(const AText, AUnitName, AFileName, AClassName: string; AKind: TFormKind;
      out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Edit für die .dpr: "AUnitName in 'AFileName'" am Ende des uses, ohne Formular (#274); in einer
    /// .dpk am Ende von contains (#299). False ohne Liste oder wenn die Unit dort schon steht.</summary>
    class function UnitProgramEdit(const AText, AUnitName, AFileName: string; out AEdit: TTextEdit): Boolean; static;
    /// <summary>Edit für die .dproj: DCCReference mit Form und gegebenenfalls DesignClass hinter
    /// dem letzten DCCReference, ohne solche vor der ersten BuildConfiguration (#297). False ohne beides.</summary>
    class function ProjectEdit(const AText, AFileName, AClassName: string; AKind: TFormKind;
      AWithForm: Boolean; out AEdit: TTextEdit): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Text.Lines;

const
  cFormUses = 'Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,' +
    '|  Vcl.Controls, Vcl.Forms, Vcl.Dialogs';
  cDataModuleUses = 'System.SysUtils, System.Classes';

class function TUnitTemplates.InstanceName(const AClassName: string): string;
begin
  if (Length(AClassName) > 1) and CharInSet(AClassName[1], ['T', 't']) then
  begin
    Result := Copy(AClassName, 2, MaxInt);
  end
  else
  begin
    Result := AClassName;
  end;
end;

class function TUnitTemplates.DefaultAncestor(AKind: TFormKind): string;
begin
  case AKind of
    TFormKind.Frame:
      Result := 'TFrame';
    TFormKind.DataModule:
      Result := 'TDataModule';
  else
    Result := 'TForm';
  end;
end;

{ TFormUnitSpec }

class function TFormUnitSpec.Create(const AUnitName, AClassName: string; AKind: TFormKind): TFormUnitSpec;
begin
  Result := Default(TFormUnitSpec);
  Result.UnitName := AUnitName;
  Result.ClassName := AClassName;
  Result.Kind := AKind;
end;

{ TUnitTemplates }

class function TUnitTemplates.FormUnit(const ASpec: TFormUnitSpec; const ALineBreak: string): string;
var
  mAncestor, mUsesList: string;
begin
  mAncestor := ASpec.Ancestor;
  if mAncestor = '' then
  begin
    mAncestor := DefaultAncestor(ASpec.Kind);
  end;
  if ASpec.Kind = TFormKind.DataModule then
  begin
    mUsesList := cDataModuleUses;
  end
  else
  begin
    mUsesList := StringReplace(cFormUses, '|', ALineBreak, []);
  end;
  if ASpec.AncestorUnit <> '' then
  begin
    mUsesList := mUsesList + ',' + ALineBreak + '  ' + ASpec.AncestorUnit;
  end;
  Result := 'unit ' + ASpec.UnitName + ';' + ALineBreak + ALineBreak +
    'interface' + ALineBreak + ALineBreak +
    'uses' + ALineBreak + '  ' + mUsesList + ';' + ALineBreak + ALineBreak +
    'type' + ALineBreak +
    Format('  %s = class(%s)', [ASpec.ClassName, mAncestor]) + ALineBreak +
    '  private' + ALineBreak + '    { Private-Deklarationen }' + ALineBreak +
    '  public' + ALineBreak + '    { Public-Deklarationen }' + ALineBreak +
    '  end;' + ALineBreak + ALineBreak;
  if ASpec.GlobalVariable then
  begin
    Result := Result + 'var' + ALineBreak +
      Format('  %s: %s;', [InstanceName(ASpec.ClassName), ASpec.ClassName]) + ALineBreak + ALineBreak;
  end;
  Result := Result + 'implementation' + ALineBreak + ALineBreak + '{$R *.dfm}' + ALineBreak + ALineBreak +
    'end.' + ALineBreak;
end;

class function TUnitTemplates.FormDfm(const AClassName: string; AKind: TFormKind; AInherited: Boolean;
  const ALineBreak: string): string;
var
  mName: string;
begin
  mName := InstanceName(AClassName);
  if AInherited then
  begin
    Result := Format('inherited %s: %s', [mName, AClassName]) + ALineBreak;
  end
  else
  begin
    Result := Format('object %s: %s', [mName, AClassName]) + ALineBreak;
  end;
  // Geerbte Formulare übernehmen alle Werte vom Vorfahren.
  if not AInherited then
    case AKind of
      TFormKind.Form:
        Result := Result + '  Left = 0' + ALineBreak + '  Top = 0' + ALineBreak +
          '  Caption = ' + QuotedStr(mName) + ALineBreak + '  ClientHeight = 441' + ALineBreak +
          '  ClientWidth = 624' + ALineBreak;
      TFormKind.Frame:
        Result := Result + '  Left = 0' + ALineBreak + '  Top = 0' + ALineBreak + '  Width = 640' + ALineBreak +
          '  Height = 480' + ALineBreak + '  TabOrder = 0' + ALineBreak;
      TFormKind.DataModule:
        Result := Result + '  Height = 480' + ALineBreak + '  Width = 640' + ALineBreak;
    end;
  Result := Result + 'end' + ALineBreak;
end;

class function TUnitTemplates.ComponentUnit(const AUnitName, AClassName, AAncestor, AAncestorUnit,
  APalette: string; const ALineBreak: string): string;
var
  mUsesList: string;
begin
  mUsesList := 'System.SysUtils, System.Classes';
  if AAncestorUnit <> '' then
  begin
    mUsesList := mUsesList + ', ' + AAncestorUnit;
  end;
  Result := 'unit ' + AUnitName + ';' + ALineBreak + ALineBreak +
    'interface' + ALineBreak + ALineBreak +
    'uses' + ALineBreak + '  ' + mUsesList + ';' + ALineBreak + ALineBreak +
    'type' + ALineBreak +
    Format('  %s = class(%s)', [AClassName, AAncestor]) + ALineBreak +
    '  private' + ALineBreak + '  protected' + ALineBreak + '  public' + ALineBreak + '  published' + ALineBreak +
    '  end;' + ALineBreak + ALineBreak +
    'procedure Register;' + ALineBreak + ALineBreak +
    'implementation' + ALineBreak + ALineBreak +
    'procedure Register;' + ALineBreak + 'begin' + ALineBreak +
    Format('  RegisterComponents(%s, [%s]);', [QuotedStr(APalette), AClassName]) + ALineBreak + 'end;' +
    ALineBreak + ALineBreak + 'end.' + ALineBreak;
end;

/// <summary>Index des Semikolons, das das erste uses abschließt; -1 ohne.</summary>
function UsesSemicolon(const ATokens: TArray<TPascalToken>): Integer;
var
  mIndex, mNext: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('uses') then
    begin
      for mNext := mIndex + 1 to High(ATokens) do
      begin
        if ATokens[mNext].IsSymbol(';') then
        begin
          Exit(mNext);
        end;
      end;
      Exit;
    end;
  end;
end;

/// <summary>Kommentar hinter dem Eintrag in der .dpr: {Name}, {Name: TFrame} bzw. {Name: TDataModule}.</summary>
function ProgramComment(const AClassName: string; AKind: TFormKind): string;
begin
  case AKind of
    TFormKind.Frame:
      Result := Format('{%s: TFrame}', [TUnitTemplates.InstanceName(AClassName)]);
    TFormKind.DataModule:
      Result := Format('{%s: TDataModule}', [TUnitTemplates.InstanceName(AClassName)]);
  else
    Result := Format('{%s}', [TUnitTemplates.InstanceName(AClassName)]);
  end;
end;

/// <summary>Edit für Application.CreateForm vor Application.Run; False ohne Application.Run.</summary>
function CreateFormEdit(const ATokens: TArray<TPascalToken>; const AClassName, ALineBreak: string;
  out AEdit: TTextEdit): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(ATokens) - 2 do
  begin
    if SameText(ATokens[mIndex].Text, 'Application') and ATokens[mIndex + 1].IsSymbol('.') and
      SameText(ATokens[mIndex + 2].Text, 'Run') then
    begin
      AEdit := TTextEdit.Create(TTextRange.Create(ATokens[mIndex].StartPos, ATokens[mIndex].StartPos),
        Format('Application.CreateForm(%s, %s);%s%s', [AClassName, TUnitTemplates.InstanceName(AClassName),
        ALineBreak, StringOfChar(' ', ATokens[mIndex].StartPos.Character)]));
      Exit(True);
    end;
  end;
end;

class function TUnitTemplates.ProgramEdits(const AText, AUnitName, AFileName, AClassName: string;
  AKind: TFormKind; out AEdits: TArray<TTextEdit>): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mSemicolon: Integer;
  mLineBreak: string;
  mEdit: TTextEdit;
begin
  AEdits := nil;
  mLineBreak := TTextLines.LineBreakOf(AText);
  mTokens := TPascalLexer.Tokenize(AText);
  mSemicolon := UsesSemicolon(mTokens);
  if mSemicolon < 0 then
  begin
    Exit(False);
  end;
  AEdits := [TTextEdit.Create(TTextRange.Create(mTokens[mSemicolon].StartPos, mTokens[mSemicolon].StartPos),
    Format(',%s  %s in %s %s', [mLineBreak, AUnitName, QuotedStr(AFileName), ProgramComment(AClassName, AKind)]))];
  // Frames erzeugt die Anwendung nicht automatisch.
  if (AKind <> TFormKind.Frame) and CreateFormEdit(mTokens, AClassName, mLineBreak, mEdit) then
  begin
    AEdits := AEdits + [mEdit];
  end;
  Result := True;
end;

function IsWordToken(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword];
end;

/// <summary>Index des ersten Worts AWord; -1 ohne.</summary>
function WordIndex(const ATokens: TArray<TPascalToken>; const AWord: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if IsWordToken(ATokens[mIndex]) and SameText(ATokens[mIndex].Text, AWord) then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Semikolon der Liste, deren Schlüsselwort an AList steht; -1, wenn die Liste AUnitName schon nennt
/// oder nicht endet. Namen bis "in", "," oder ";" zusammensetzen; Pfade und Kommentare zählen nicht.</summary>
function ListSemicolon(const ATokens: TArray<TPascalToken>; AList: Integer; const AUnitName: string): Integer;
var
  mNext: Integer;
  mName: string;
  mInName: Boolean;
begin
  Result := -1;
  mName := '';
  mInName := True;
  for mNext := AList + 1 to High(ATokens) do
  begin
    if ATokens[mNext].IsSymbol(';') or ATokens[mNext].IsSymbol(',') then
    begin
      if SameText(mName, AUnitName) then
      begin
        Exit(-1);
      end;
      mName := '';
      mInName := True;
      if ATokens[mNext].IsSymbol(';') then
      begin
        Exit(mNext);
      end;
    end
    else if ATokens[mNext].IsKeyword('in') then
    begin
      mInName := False;
    end
    else if mInName and (IsWordToken(ATokens[mNext]) or ATokens[mNext].IsSymbol('.')) then
    begin
      mName := mName + ATokens[mNext].Text;
    end;
  end;
end;

class function TUnitTemplates.UnitProgramEdit(const AText, AUnitName, AFileName: string;
  out AEdit: TTextEdit): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mList, mSemicolon: Integer;
begin
  AEdit := Default(TTextEdit);
  mTokens := TPascalLexer.Tokenize(AText);
  // Packages führen ihre Units unter contains, Programme unter uses.
  mList := WordIndex(mTokens, 'contains');
  if mList < 0 then
  begin
    mList := WordIndex(mTokens, 'uses');
  end;
  mSemicolon := -1;
  if mList >= 0 then
  begin
    mSemicolon := ListSemicolon(mTokens, mList, AUnitName);
  end;
  Result := mSemicolon >= 0;
  if Result then
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(mTokens[mSemicolon].StartPos, mTokens[mSemicolon].StartPos),
      Format(',%s  %s in %s', [TTextLines.LineBreakOf(AText), AUnitName, QuotedStr(AFileName)]));
  end;
end;

/// <summary>Letzte Zeile des letzten DCCReference (mehrzeilig bis zum schließenden Tag); -1 ohne.</summary>
function LastReferenceLine(const ALines: TArray<string>): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ALines) do
  begin
    if Pos('<DCCReference ', ALines[mIndex]) > 0 then
    begin
      Result := mIndex;
      while (Result < High(ALines)) and not EndsText('/>', TrimRight(ALines[Result])) and
        (Pos('</DCCReference>', ALines[Result]) = 0) do
      begin
        Inc(Result);
      end;
    end;
  end;
end;

/// <summary>Projekt ohne Units (Konsolenprogramm): Eintrag vor die erste BuildConfiguration im selben
/// ItemGroup; False ohne.</summary>
function FirstReferenceEdit(const ALines: TArray<string>; const AFileName, ALineBreak: string;
  out AEdit: TTextEdit): Boolean;
var
  mIndex: Integer;
  mIndent: string;
begin
  Result := False;
  for mIndex := 0 to High(ALines) do
  begin
    if Pos('<BuildConfiguration ', ALines[mIndex]) > 0 then
    begin
      mIndent := Copy(ALines[mIndex], 1, Pos('<', ALines[mIndex]) - 1);
      AEdit := TTextEdit.Create(TTextRange.Create(mIndex, 0, mIndex, 0),
        Format('%s<DCCReference Include="%s"/>', [mIndent, AFileName]) + ALineBreak);
      Exit(True);
    end;
  end;
end;

class function TUnitTemplates.ProjectEdit(const AText, AFileName, AClassName: string; AKind: TFormKind;
  AWithForm: Boolean; out AEdit: TTextEdit): Boolean;
var
  mLines: TArray<string>;
  mLast: Integer;
  mIndent, mLB, mText: string;
begin
  mLB := TTextLines.LineBreakOf(AText);
  mLines := AText.Split([mLB]);
  mLast := LastReferenceLine(mLines);
  if mLast < 0 then
  begin
    Exit(FirstReferenceEdit(mLines, AFileName, mLB, AEdit));
  end;
  mIndent := Copy(mLines[mLast], 1, Pos('<', mLines[mLast]) - 1);
  if not AWithForm then
  begin
    mText := Format('%s<DCCReference Include="%s"/>', [mIndent, AFileName]);
  end
  else
  begin
    mText := Format('%s<DCCReference Include="%s">', [mIndent, AFileName]) + mLB +
      Format('%s    <Form>%s</Form>', [mIndent, TUnitTemplates.InstanceName(AClassName)]);
    if AKind <> TFormKind.Form then
    begin
      mText := mText + mLB + Format('%s    <FormType>dfm</FormType>', [mIndent]) + mLB +
        Format('%s    <DesignClass>%s</DesignClass>', [mIndent, TUnitTemplates.DefaultAncestor(AKind)]);
    end;
    mText := mText + mLB + mIndent + '</DCCReference>';
  end;
  AEdit := TTextEdit.Create(TTextRange.Create(mLast, Length(mLines[mLast]), mLast, Length(mLines[mLast])), mLB + mText);
  Result := True;
end;

end.
