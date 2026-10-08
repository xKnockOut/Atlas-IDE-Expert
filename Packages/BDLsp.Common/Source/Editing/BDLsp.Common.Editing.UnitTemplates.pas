unit BDLsp.Common.Editing.UnitTemplates;

// Gerüste für neue Formulare, Frames, Datenmodule und Komponenten (#299):
// Unit-Text, DFM und die Einträge in .dpr und .dproj, wie die IDE sie anlegt.
// Reine Textfunktionen; Anlegen der Dateien und Öffnen übernimmt der Aufrufer.

interface

uses
  BDLsp.Common.Rules.Contract;

type
  TFormKind = (Form, Frame, DataModule);

  TUnitTemplates = class
  public
    /// <summary>Name der Instanz bzw. Datei zum Klassennamen: TKundenForm wird KundenForm.</summary>
    class function InstanceName(const AClassName: string): string; static;
    /// <summary>Standard-Vorfahr der Art: TForm, TFrame, TDataModule.</summary>
    class function DefaultAncestor(AKind: TFormKind): string; static;
    /// <summary>Unit zu einem Formular. AAncestor leer = Standard der Art; AAncestorUnit kommt zusätzlich ins uses.</summary>
    class function FormUnit(const AUnitName, AClassName, AAncestor, AAncestorUnit: string; AKind: TFormKind;
      AGlobalVariable: Boolean; const ALineBreak: string): string; static;
    /// <summary>DFM zum Formular; AInherited für geerbte Formulare ("inherited" statt "object").</summary>
    class function FormDfm(const AClassName: string; AKind: TFormKind; AInherited: Boolean;
      const ALineBreak: string): string; static;
    /// <summary>Unit einer neuen Komponente mit published-Abschnitt und Register.</summary>
    class function ComponentUnit(const AUnitName, AClassName, AAncestor, AAncestorUnit, APalette: string;
      const ALineBreak: string): string; static;
    /// <summary>Edits für die .dpr: Eintrag im uses mit {Kommentar} und bei Formularen und
    /// Datenmodulen Application.CreateForm vor Application.Run. False ohne uses.</summary>
    class function ProgramEdits(const AText, AUnitName, AFileName, AClassName: string; AKind: TFormKind;
      out AEdits: TArray<TRuleEdit>): Boolean; static;
    /// <summary>Edit für die .dproj: DCCReference mit Form und gegebenenfalls DesignClass hinter
    /// dem letzten DCCReference. False ohne DCCReference.</summary>
    class function ProjectEdit(const AText, AFileName, AClassName: string; AKind: TFormKind;
      AWithForm: Boolean; out AEdit: TRuleEdit): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.Lexer;

const
  FormUses = 'Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,' +
    '|  Vcl.Controls, Vcl.Forms, Vcl.Dialogs';
  DataModuleUses = 'System.SysUtils, System.Classes';

class function TUnitTemplates.InstanceName(const AClassName: string): string;
begin
  if (Length(AClassName) > 1) and CharInSet(AClassName[1], ['T', 't']) then
    Result := Copy(AClassName, 2, MaxInt)
  else
    Result := AClassName;
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

class function TUnitTemplates.FormUnit(const AUnitName, AClassName, AAncestor, AAncestorUnit: string;
  AKind: TFormKind; AGlobalVariable: Boolean; const ALineBreak: string): string;
var
  Ancestor, UsesList: string;
begin
  Ancestor := AAncestor;
  if Ancestor = '' then
    Ancestor := DefaultAncestor(AKind);
  if AKind = TFormKind.DataModule then
    UsesList := DataModuleUses
  else
    UsesList := StringReplace(FormUses, '|', ALineBreak, []);
  if AAncestorUnit <> '' then
    UsesList := UsesList + ',' + ALineBreak + '  ' + AAncestorUnit;
  Result := 'unit ' + AUnitName + ';' + ALineBreak + ALineBreak +
    'interface' + ALineBreak + ALineBreak +
    'uses' + ALineBreak + '  ' + UsesList + ';' + ALineBreak + ALineBreak +
    'type' + ALineBreak +
    Format('  %s = class(%s)', [AClassName, Ancestor]) + ALineBreak +
    '  private' + ALineBreak + '    { Private-Deklarationen }' + ALineBreak +
    '  public' + ALineBreak + '    { Public-Deklarationen }' + ALineBreak +
    '  end;' + ALineBreak + ALineBreak;
  if AGlobalVariable then
    Result := Result + 'var' + ALineBreak + Format('  %s: %s;', [InstanceName(AClassName), AClassName]) +
      ALineBreak + ALineBreak;
  Result := Result + 'implementation' + ALineBreak + ALineBreak + '{$R *.dfm}' + ALineBreak + ALineBreak +
    'end.' + ALineBreak;
end;

class function TUnitTemplates.FormDfm(const AClassName: string; AKind: TFormKind; AInherited: Boolean;
  const ALineBreak: string): string;
var
  Name: string;
begin
  Name := InstanceName(AClassName);
  if AInherited then
    Result := Format('inherited %s: %s', [Name, AClassName]) + ALineBreak
  else
    Result := Format('object %s: %s', [Name, AClassName]) + ALineBreak;
  // Geerbte Formulare übernehmen alle Werte vom Vorfahren.
  if not AInherited then
    case AKind of
      TFormKind.Form:
        Result := Result + '  Left = 0' + ALineBreak + '  Top = 0' + ALineBreak +
          '  Caption = ' + QuotedStr(Name) + ALineBreak + '  ClientHeight = 441' + ALineBreak +
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
  UsesList: string;
begin
  UsesList := 'System.SysUtils, System.Classes';
  if AAncestorUnit <> '' then
    UsesList := UsesList + ', ' + AAncestorUnit;
  Result := 'unit ' + AUnitName + ';' + ALineBreak + ALineBreak +
    'interface' + ALineBreak + ALineBreak +
    'uses' + ALineBreak + '  ' + UsesList + ';' + ALineBreak + ALineBreak +
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

function LineBreakOf(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
    Result := #13#10
  else
    Result := #10;
end;

class function TUnitTemplates.ProgramEdits(const AText, AUnitName, AFileName, AClassName: string;
  AKind: TFormKind; out AEdits: TArray<TRuleEdit>): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Next, Semicolon: Integer;
  Comment, LB: string;
begin
  AEdits := nil;
  LB := LineBreakOf(AText);
  Tokens := TPascalLexer.Tokenize(AText);
  Semicolon := -1;
  for Index := 0 to High(Tokens) do
    if Tokens[Index].IsKeyword('uses') then
    begin
      for Next := Index + 1 to High(Tokens) do
        if Tokens[Next].IsSymbol(';') then
        begin
          Semicolon := Next;
          Break;
        end;
      Break;
    end;
  if Semicolon < 0 then
    Exit(False);
  case AKind of
    TFormKind.Frame:
      Comment := Format('{%s: TFrame}', [TUnitTemplates.InstanceName(AClassName)]);
    TFormKind.DataModule:
      Comment := Format('{%s: TDataModule}', [TUnitTemplates.InstanceName(AClassName)]);
  else
    Comment := Format('{%s}', [TUnitTemplates.InstanceName(AClassName)]);
  end;
  AEdits := [TRuleEdit.Create(TTextRange.Create(Tokens[Semicolon].StartPos, Tokens[Semicolon].StartPos),
    Format(',%s  %s in %s %s', [LB, AUnitName, QuotedStr(AFileName), Comment]))];
  // Frames erzeugt die Anwendung nicht automatisch.
  if AKind <> TFormKind.Frame then
    for Index := 0 to High(Tokens) - 2 do
      if SameText(Tokens[Index].Text, 'Application') and Tokens[Index + 1].IsSymbol('.') and
        SameText(Tokens[Index + 2].Text, 'Run') then
      begin
        AEdits := AEdits + [TRuleEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].StartPos),
          Format('Application.CreateForm(%s, %s);%s%s', [AClassName, TUnitTemplates.InstanceName(AClassName), LB,
          StringOfChar(' ', Tokens[Index].StartPos.Character)]))];
        Break;
      end;
  Result := True;
end;

class function TUnitTemplates.ProjectEdit(const AText, AFileName, AClassName: string; AKind: TFormKind;
  AWithForm: Boolean; out AEdit: TRuleEdit): Boolean;
var
  Lines: TArray<string>;
  Index, Last: Integer;
  Indent, LB, Text: string;
begin
  LB := LineBreakOf(AText);
  Lines := AText.Split([LB]);
  Last := -1;
  for Index := 0 to High(Lines) do
    if Pos('<DCCReference ', Lines[Index]) > 0 then
    begin
      Last := Index;
      // Mehrzeiliger Eintrag: bis zum schließenden Tag.
      while (Last < High(Lines)) and not EndsText('/>', TrimRight(Lines[Last])) and
        (Pos('</DCCReference>', Lines[Last]) = 0) do
        Inc(Last);
    end;
  if Last < 0 then
    Exit(False);
  Indent := Copy(Lines[Last], 1, Pos('<', Lines[Last]) - 1);
  if not AWithForm then
    Text := Format('%s<DCCReference Include="%s"/>', [Indent, AFileName])
  else
  begin
    Text := Format('%s<DCCReference Include="%s">', [Indent, AFileName]) + LB +
      Format('%s    <Form>%s</Form>', [Indent, TUnitTemplates.InstanceName(AClassName)]);
    if AKind <> TFormKind.Form then
      Text := Text + LB + Format('%s    <FormType>dfm</FormType>', [Indent]) + LB +
        Format('%s    <DesignClass>%s</DesignClass>', [Indent, TUnitTemplates.DefaultAncestor(AKind)]);
    Text := Text + LB + Indent + '</DCCReference>';
  end;
  AEdit := TRuleEdit.Create(TTextRange.Create(Last, Length(Lines[Last]), Last, Length(Lines[Last])), LB + Text);
  Result := True;
end;

end.
