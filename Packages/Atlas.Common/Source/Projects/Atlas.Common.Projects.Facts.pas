unit Atlas.Common.Projects.Facts;

// Was Prüfungen über ein Projekt aus seinen Dateien wissen: Anwendungsart aus Hauptquelltext und .dproj (#943,
// #1060), automatisch erzeugte Formulare der .dpr (#956), das Package, das eine Unit enthält, und Warnschalter der
// .dproj (#1378). Der Arbeitsbereich und der Linter tragen damit TCheckProject und TCheckServices zusammen, einzelne
// Prüfregeln lesen die Art auch selbst aus dem Text.

interface

uses
  Atlas.Common.Projects.Contract.Group,
  Atlas.Common.Projects.PackageReader;

type
  TProjectFacts = class
  public
    /// <summary>Anwendungsart aus DCC_ConsoleTarget der .dproj und dem Text der .dpr: Console bei
    /// "true" oder {$APPTYPE CONSOLE}, Service bei einem program mit Vcl.SvcMgr und ohne Vcl.Forms,
    /// sonst Gui bei einem program; Library_ bei einer library ohne Formulare und ohne Vcl.Forms,
    /// Package bei einem package, sonst Unknown (DLL mit Formularen, kein Text).</summary>
    class function ApplicationKind(const AConsoleTarget, AMainSource: string): TApplicationKind; static;
    /// <summary>Variablen aus Application.CreateForm(TKlasse, Variable) der .dpr in Aufrufreihenfolge.</summary>
    class function AutoCreatedForms(const AMainSource: string): TArray<string>; static;
    /// <summary>AutoCreatedForms des ersten Programms aus APrograms (Quelltexte der .dpr), dessen uses die Unit
    /// AUnitName nennt; nil ohne (Linter, Golden-Korpus).</summary>
    class function FormsOfProgram(const APrograms: TArray<string>; const AUnitName: string): TArray<string>; static;
    /// <summary>Name des Packages aus APackages, dessen contains die Unit AUnitName nennt; sonst ''.</summary>
    class function PackageNameOf(const APackages: TArray<TPackageSource>; const AUnitName: string): string; static;
    /// <summary>Eintrag für TCheckServices.ProjectWarnings aus einer Eigenschaft der .dproj ("DCC_SYMBOL_PLATFORM",
    /// "false" ergibt "SYMBOL_PLATFORM=false"; DCC_Warnings ergibt "WARNINGS=…"); '' für andere Eigenschaften.
    /// </summary>
    class function WarningEntry(const AProperty, AValue: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.UsesClauses;

const
  cPropertyPrefix = 'DCC_';
  cWarningsName = 'WARNINGS';

function IsIdentifierNamed(const AToken: TPascalToken; const AName: string): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Identifier) and SameText(AToken.Text, AName);
end;

type
  /// <summary>Was TProjectFacts.ApplicationKind beim Lesen der Hauptdatei sammelt.</summary>
  TMainSourceFacts = record
    Kind: TApplicationKind;
    /// <summary>Steht die Art fest (Konsole, Package, keine Hauptdatei)?</summary>
    Done: Boolean;
    First, ServiceManager, Forms, FormMarker, AfterFileName: Boolean;
    procedure Add(const AToken: TPascalToken);
    procedure AddDirective(const AText: string);
    procedure AddComment(const AText: string);
    procedure AddCode(const AToken: TPascalToken);
    procedure Start(const AToken: TPascalToken);
    /// <summary>Art nach dem ganzen Text: Dienst, Bibliothek mit Formularen …</summary>
    function Final: TApplicationKind;
  end;

{ TMainSourceFacts }

procedure TMainSourceFacts.Add(const AToken: TPascalToken);
begin
  case AToken.Kind of
    TPascalTokenKind.Directive:
      AddDirective(AToken.Text);
    TPascalTokenKind.Comment:
      AddComment(AToken.Text);
  else
    AddCode(AToken);
  end;
end;

procedure TMainSourceFacts.AddDirective(const AText: string);
var
  mDirective: string;
begin
  // {$APPTYPE CONSOLE} oder (*$APPTYPE CONSOLE*), auch in {$IFDEF}: dann gilt Konsole.
  mDirective := UpperCase(AText);
  mDirective := StringReplace(StringReplace(mDirective, '(*$', '', []), '{$', '', []);
  if StartsText('APPTYPE', Trim(mDirective)) and ContainsText(mDirective, 'CONSOLE') then
  begin
    Kind := TApplicationKind.Console;
    Done := True;
  end;
end;

procedure TMainSourceFacts.AddComment(const AText: string);
begin
  // Unit1 in 'Unit1.pas' {Form1}: die IDE markiert Formulare ohne Doppelpunkt, andere Designer
  // als {Name: TDataModule} (#1060).
  if AfterFileName and StartsStr('{', AText) and ((Pos(':', AText) = 0) or ContainsText(AText, ': TForm')) then
  begin
    FormMarker := True;
  end;
end;

procedure TMainSourceFacts.AddCode(const AToken: TPascalToken);
begin
  AfterFileName := AToken.Kind = TPascalTokenKind.StringLiteral;
  ServiceManager := ServiceManager or IsIdentifierNamed(AToken, 'SvcMgr');
  Forms := Forms or IsIdentifierNamed(AToken, 'Forms');
  if First then
  begin
    First := False;
    Start(AToken);
  end;
end;

procedure TMainSourceFacts.Start(const AToken: TPascalToken);
begin
  if AToken.IsKeyword('program') then
  begin
    Kind := TApplicationKind.Gui;
  end
  else if AToken.IsKeyword('library') then
  begin
    Kind := TApplicationKind.Library_;
  end
  // package ist kein reserviertes Wort (#943).
  else if IsIdentifierNamed(AToken, 'package') then
  begin
    Kind := TApplicationKind.Package;
    Done := True;
  end
  else
  begin
    Kind := TApplicationKind.Unknown;
    Done := True;
  end;
end;

function TMainSourceFacts.Final: TApplicationKind;
begin
  Result := Kind;
  if Done then
  begin
    Exit;
  end;
  // Ein Dienst bindet Vcl.SvcMgr ein; mit Vcl.Forms daneben startet dasselbe Programm auch mit Oberfläche.
  if (Result = TApplicationKind.Gui) and ServiceManager and not Forms then
  begin
    Result := TApplicationKind.Service;
  end;
  if (Result = TApplicationKind.Library_) and (Forms or FormMarker) then
  begin
    Result := TApplicationKind.Unknown;
  end;
end;

{ TProjectFacts }

class function TProjectFacts.ApplicationKind(const AConsoleTarget, AMainSource: string): TApplicationKind;
var
  mTokens: TArray<TPascalToken>;
  mFacts: TMainSourceFacts;
  mIndex: Integer;
begin
  if SameText(Trim(AConsoleTarget), 'true') then
  begin
    Exit(TApplicationKind.Console);
  end;
  mTokens := TPascalLexer.Tokenize(AMainSource);
  mFacts := Default(TMainSourceFacts);
  mFacts.Kind := TApplicationKind.Unknown;
  mFacts.First := True;
  mIndex := 0;
  while not mFacts.Done and (mIndex <= High(mTokens)) do
  begin
    mFacts.Add(mTokens[mIndex]);
    Inc(mIndex);
  end;
  Result := mFacts.Final;
end;

class function TProjectFacts.AutoCreatedForms(const AMainSource: string): TArray<string>;
var
  mTokens: TArray<TPascalToken>;
  mCode: TArray<Integer>;
  mIndex, mPosition: Integer;

  function IsText(APosition: Integer; const AText: string): Boolean;
  begin
    Result := (APosition <= High(mCode)) and SameText(mTokens[mCode[APosition]].Text, AText);
  end;

  /// <summary>Steht ab APosition "Application.CreateForm(Klasse, Name)" mit einem Bezeichner als Name?</summary>
  function IsCreateForm(APosition: Integer): Boolean;
  begin
    Result := IsText(APosition, 'Application') and IsText(APosition + 1, '.') and
      IsText(APosition + 2, 'CreateForm') and IsText(APosition + 3, '(');
    Result := Result and IsText(APosition + 5, ',') and IsText(APosition + 7, ')') and
      (mTokens[mCode[APosition + 6]].Kind = TPascalTokenKind.Identifier);
  end;

begin
  Result := nil;
  mTokens := TPascalLexer.Tokenize(AMainSource);
  mCode := nil;
  for mIndex := 0 to High(mTokens) do
  begin
    if not (mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      mCode := mCode + [mIndex];
    end;
  end;
  // Application.CreateForm(TfrmHaupt, frmHaupt);
  for mPosition := 0 to High(mCode) - 7 do
  begin
    if IsCreateForm(mPosition) then
    begin
      Result := Result + [mTokens[mCode[mPosition + 6]].Text];
    end;
  end;
end;

class function TProjectFacts.FormsOfProgram(const APrograms: TArray<string>;
  const AUnitName: string): TArray<string>;
var
  mMain: string;
begin
  for mMain in APrograms do
  begin
    if MatchText(AUnitName, TPascalUses.UsedUnitsOf(mMain)) then
    begin
      Exit(AutoCreatedForms(mMain));
    end;
  end;
  Result := nil;
end;

class function TProjectFacts.PackageNameOf(const APackages: TArray<TPackageSource>;
  const AUnitName: string): string;
var
  mSource: TPackageSource;
begin
  for mSource in APackages do
  begin
    if mSource.IsPackage and (mSource.ContainsIndex(AUnitName) >= 0) then
    begin
      Exit(mSource.Name);
    end;
  end;
  Result := '';
end;

class function TProjectFacts.WarningEntry(const AProperty, AValue: string): string;
var
  mName: string;
begin
  Result := '';
  if not StartsText(cPropertyPrefix, AProperty) then
  begin
    Exit;
  end;
  mName := UpperCase(Copy(AProperty, Length(cPropertyPrefix) + 1, MaxInt));
  if (mName <> cWarningsName) and (IndexText(mName, TDirectiveNames.Warnings) < 0) then
  begin
    Exit;
  end;
  Result := mName + '=' + LowerCase(Trim(AValue));
end;

end.
