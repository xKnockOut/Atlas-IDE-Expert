unit Atlas.Common.Editing.MoveMember;

// „Mitglied in Vorfahr oder Nachfahr verschieben“ (#675, Pull up / Push down):
// Felder, Methoden und Properties einer Klasse wandern eine Ebene (oder
// mehrere) in der Vererbung nach oben bzw. in direkte Nachfahren nach unten.
//
// Nach oben (PullUp) in einen Vorfahren des Projekts:
//   - Was ganz wandert, darf nur Mitglieder benutzen, die mitwandern;
//     Methoden können stattdessen oben virtual; abstract; werden, der Rumpf
//     bleibt dann unten mit override.
//   - Namen, die der Vorfahr schon hat, brechen ab.
//   - Ein privates Mitglied, das unten weiter benutzt wird, wird protected
//     bzw. strict protected (in derselben Unit nur strict private).
//   - Andere Nachfahren des Ziels mit einer gleichnamigen Methode derselben
//     Signatur: Auf Wunsch wird die Methode oben virtual und dort override;
//     sonst nennt der Plan sie als Hinweis.
// Nach unten (PushDown) in gewählte direkte Nachfahren:
//   - Benutzt die Klasse selbst oder fremder Code (Fundstellen vom Aufrufer)
//     das Mitglied weiter, bricht es ab; Methoden können stattdessen im
//     Vorfahren abstrakt bleiben, die Nachfahren überschreiben sie.
//   - Benutzte Mitglieder bleiben oben; sind sie für die Nachfahren nicht
//     sichtbar, werden sie protected bzw. strict protected, ebenso private
//     Methoden, die abstrakt oben bleiben (die Nachfahren überschreiben sie).
//   - Namen, die ein Nachfahr schon hat, brechen ab (außer seiner
//     Überschreibung einer im Vorfahren abstrakt bleibenden Methode).
//
// Die Texte aller betroffenen Dateien liegen in TMemberFiles; der Umbau
// ändert sie Schritt für Schritt (anwenden, neu parsen). uses-Einträge
// ergänzt Atlas.Common.Lsp.MoveMember.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.MemberTransfer;

type
  {$SCOPEDENUMS ON}
  TMoveDirection = (Up, Down);
  {$SCOPEDENUMS OFF}

  /// <summary>Texte der beteiligten Dateien: der Stand vorher und der aktuelle.</summary>
  TMemberFiles = class
  private
    FNames: TArray<string>;
    FOriginals: TArray<string>;
    FTexts: TArray<string>;
    function IndexOf(const AFileName: string): Integer;
  public
    /// <summary>Datei mit ihrem Text aufnehmen; schon vorhanden: nichts.</summary>
    procedure Add(const AFileName, AText: string);
    function Has(const AFileName: string): Boolean;
    function Text(const AFileName: string): string;
    procedure Put(const AFileName, AText: string);
    function Original(const AFileName: string): string;
    function Changed(const AFileName: string): Boolean;
    function Files: TArray<string>;
  end;

  /// <summary>Klasse in einer Datei.</summary>
  TMemberClassRef = record
    FileName: string;
    ClassName: string;
    class function Create(const AFileName, AClassName: string): TMemberClassRef; static;
  end;

  /// <summary>Fundstelle eines Mitglieds außerhalb der Klasse und der Ziele (Text wie "Main.pas:12").</summary>
  TMemberUsage = record
    Id: Integer;
    Where: string;
    class function Create(AId: Integer; const AWhere: string): TMemberUsage; static;
  end;

  TMoveMemberInfo = record
    ClassName: string;
    /// <summary>Mitglied an der Zeile; -1 ohne.</summary>
    Selected: Integer;
    SelectedName: string;
    /// <summary>Erster Eintrag der Vorfahrenliste; '' ohne.</summary>
    Ancestor: string;
    Candidates: TArray<TTransferCandidate>;
  end;

  TMoveMemberRequest = record
    /// <summary>Ids der gewählten Mitglieder.</summary>
    Members: TArray<Integer>;
    /// <summary>Nach oben: Methoden, die oben abstrakt werden (Teilmenge von Members).</summary>
    Abstract: TArray<Integer>;
    /// <summary>Nach oben: andere Nachfahren des Ziels.</summary>
    Siblings: TArray<TMemberClassRef>;
    /// <summary>Nach oben: gleichnamige Methoden der anderen Nachfahren werden override.</summary>
    OverrideSiblings: Boolean;
    /// <summary>Nach unten: Methoden bleiben im Vorfahren abstrakt.</summary>
    KeepAbstract: Boolean;
    /// <summary>Nach unten: Fundstellen außerhalb der Klasse und der Ziele.</summary>
    Usages: TArray<TMemberUsage>;
    /// <summary>Nach unten: Zahl aller direkten Nachfahren (Hinweis, wenn nicht alle gewählt sind).</summary>
    AllTargets: Integer;
    /// <summary>Protected_ oder StrictProtected.</summary>
    RaiseVisibility: TClassVisibility;
  end;

  TMoveMemberPlan = record
    Moved: TArray<string>;
    Abstracts: TArray<string>;
    Raised: TArray<string>;
    /// <summary>Methoden anderer Klassen, die override bekommen haben ("TOther.Run").</summary>
    Overridden: TArray<string>;
    Warnings: TArray<string>;
  end;

  TMoveMember = class
  public const
    Kind = 'refactor.move';
  public
    /// <summary>Kandidaten der Klasse an ALine und das Mitglied dort; False mit Grund ohne Mitglied.</summary>
    class function Prepare(ATree: TSyntaxTree; const AText: string; ALine: Integer; out AInfo: TMoveMemberInfo;
      out AReason: string): Boolean; static;
    /// <summary>Gewählte Mitglieder von ASource in den Vorfahren ATarget. Liest und schreibt AFiles (alle
    /// beteiligten Dateien samt Geschwistern müssen darin stehen).</summary>
    class function PullUp(AFiles: TMemberFiles; const ASource, ATarget: TMemberClassRef;
      const ARequest: TMoveMemberRequest; out APlan: TMoveMemberPlan; out AReason: string): Boolean; static;
    /// <summary>Gewählte Mitglieder von ASource in die direkten Nachfahren ATargets.</summary>
    class function PushDown(AFiles: TMemberFiles; const ASource: TMemberClassRef;
      const ATargets: TArray<TMemberClassRef>; const ARequest: TMoveMemberRequest; out APlan: TMoveMemberPlan;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.TextChanges;

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

/// <summary>Name ohne Typparameter ("TBase&lt;T&gt;" → "TBase").</summary>
function PlainName(const AName: string): string;
begin
  Result := Trim(AName);
  if Pos('<', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos('<', Result) - 1));
  end;
end;

/// <summary>Ruft der Rumpf inherited auf?</summary>
function CallsInherited(ABody: TSyntaxNode): Boolean;
var
  Found: Boolean;
begin
  if ABody = nil then
  begin
    Exit(False);
  end;
  Found := False;
  ABody.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.InheritedExpr then
      begin
        Found := True;
      end;
      Result := not Found;
    end);
  Result := Found;
end;

/// <summary>Gewählte Ids prüfen: Kandidat, wählbar, ohne Doppelte.</summary>
function Chosen(const ACandidates: TArray<TTransferCandidate>; const AIds: TArray<Integer>;
  out AChosen: TArray<Integer>; out AReason: string): Boolean;
var
  Id, Index: Integer;
begin
  AChosen := nil;
  if AIds = nil then
  begin
    Exit(Fail('Bitte mindestens ein Mitglied wählen.', AReason));
  end;
  for Id in AIds do
  begin
    Index := TMemberTransfer.IndexOf(ACandidates, Id);
    if Index < 0 then
    begin
      Exit(Fail(Format('Mitglied %d ist kein Kandidat.', [Id]), AReason));
    end;
    if not ACandidates[Index].Enabled then
    begin
      Exit(Fail(Format('%s kann nicht wandern: %s.', [ACandidates[Index].Name, ACandidates[Index].Reason]), AReason));
    end;
    if not TMemberTransfer.Has(AChosen, Id) then
    begin
      AChosen := AChosen + [Id];
    end;
  end;
  AReason := '';
  Result := True;
end;

{ TMemberFiles }

function TMemberFiles.IndexOf(const AFileName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FNames) do
  begin
    if SameText(FNames[Index], AFileName) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

procedure TMemberFiles.Add(const AFileName, AText: string);
begin
  if IndexOf(AFileName) >= 0 then
  begin
    Exit;
  end;
  FNames := FNames + [AFileName];
  FOriginals := FOriginals + [AText];
  FTexts := FTexts + [AText];
end;

function TMemberFiles.Has(const AFileName: string): Boolean;
begin
  Result := IndexOf(AFileName) >= 0;
end;

function TMemberFiles.Text(const AFileName: string): string;
var
  Index: Integer;
begin
  Index := IndexOf(AFileName);
  if Index < 0 then
  begin
    Exit('');
  end;
  Result := FTexts[Index];
end;

procedure TMemberFiles.Put(const AFileName, AText: string);
var
  Index: Integer;
begin
  Index := IndexOf(AFileName);
  if Index < 0 then
  begin
    Add(AFileName, AText);
  end
  else
  begin
    FTexts[Index] := AText;
  end;
end;

function TMemberFiles.Original(const AFileName: string): string;
var
  Index: Integer;
begin
  Index := IndexOf(AFileName);
  if Index < 0 then
  begin
    Exit('');
  end;
  Result := FOriginals[Index];
end;

function TMemberFiles.Changed(const AFileName: string): Boolean;
var
  Index: Integer;
begin
  Index := IndexOf(AFileName);
  Result := (Index >= 0) and (FTexts[Index] <> FOriginals[Index]);
end;

function TMemberFiles.Files: TArray<string>;
begin
  Result := Copy(FNames);
end;

{ TMemberClassRef }

class function TMemberClassRef.Create(const AFileName, AClassName: string): TMemberClassRef;
begin
  Result.FileName := AFileName;
  Result.ClassName := AClassName;
end;

{ TMemberUsage }

class function TMemberUsage.Create(AId: Integer; const AWhere: string): TMemberUsage;
begin
  Result.Id := AId;
  Result.Where := AWhere;
end;

{ TMoveMember }

class function TMoveMember.Prepare(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  out AInfo: TMoveMemberInfo; out AReason: string): Boolean;
var
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Member: Integer;
begin
  AInfo := Default(TMoveMemberInfo);
  AInfo.Selected := -1;
  AReason := '';
  Decl := TClassLayout.DeclAt(ATree, ALine, True);
  if Decl = nil then
  begin
    Exit(Fail('An dieser Stelle steht keine Klasse.', AReason));
  end;
  Layout := TClassLayout.Read(ATree, AText, Decl);
  try
    AInfo.ClassName := Layout.Name;
    if Layout.Ancestors <> nil then
    begin
      AInfo.Ancestor := Layout.Ancestors[0];
    end;
    AInfo.Candidates := TMemberTransfer.Candidates(Layout);
    Member := Layout.MemberAtLine(ALine);
    if (Member < 0) or (TMemberTransfer.IndexOf(AInfo.Candidates, Member) < 0) then
    begin
      Exit(Fail('An dieser Stelle steht kein Feld, keine Methode und keine Property.', AReason));
    end;
    if not AInfo.Candidates[TMemberTransfer.IndexOf(AInfo.Candidates, Member)].Enabled then
    begin
      Exit(Fail(Format('%s kann nicht wandern: %s.', [Layout.Members[Member].Name,
        AInfo.Candidates[TMemberTransfer.IndexOf(AInfo.Candidates, Member)].Reason]), AReason));
    end;
    AInfo.Selected := Member;
    AInfo.SelectedName := Layout.Members[Member].Name;
  finally
    Layout.Free;
  end;
  Result := True;
end;

/// <summary>Stimmen die Typparameter überein (ohne Einschränkungen)?</summary>
function SameGenerics(ASource, ATarget: TClassLayout; out AReason: string): Boolean;
begin
  AReason := '';
  Result := SameText(StringReplace(ASource.GenericParams, ' ', '', [rfReplaceAll]),
    StringReplace(ATarget.GenericParams, ' ', '', [rfReplaceAll]));
  if not Result then
  begin
    AReason := Format('%s und %s haben verschiedene Typparameter; Rümpfe ließen sich nicht übertragen.',
      [ASource.Name, ATarget.Name]);
  end;
end;

type
  /// <summary>Gleichnamige Methode eines anderen Nachfahren, die override bekommt.</summary>
  TSiblingHit = record
    Ref: TMemberClassRef;
    Member: TClassMember;
  end;

  /// <summary>Ablauf von PullUp mit seinem Zwischenstand.</summary>
  TPullUp = record
    Files: TMemberFiles;
    SourceRef: TMemberClassRef;
    TargetRef: TMemberClassRef;
    Request: TMoveMemberRequest;
    Source: TClassLayout;
    Target: TClassLayout;
    Candidates: TArray<TTransferCandidate>;
    Picked: TArray<Integer>;
    Moved: TArray<Integer>;
    Abstracts: TArray<Integer>;
    Virtualize: TArray<Integer>;
    Raised: TArray<Integer>;
    Hits: TArray<TSiblingHit>;
    Plan: TMoveMemberPlan;
    function Run(out AReason: string): Boolean;
    /// <summary>Gewählte in ganz wandernde und abstrakt werdende teilen und prüfen.</summary>
    function Split(out AReason: string): Boolean;
    procedure CompareSiblings;
    procedure CompareSibling(ASibling: TClassLayout; const ARef: TMemberClassRef);
    procedure CompareMethod(ASibling: TClassLayout; const ARef: TMemberClassRef; AId, AIndex: Integer);
    /// <summary>Sichtbarkeit oben; gehobene abstrakte Methoden unten in denselben Abschnitt (sonst H2269).
    /// </summary>
    procedure RaiseUsed;
    function DeclarationOf(AId: Integer): TTransferDeclaration;
    function BodyOf(AId: Integer): string;
    procedure Collect(out ADeclarations: TArray<TTransferDeclaration>; out ABodies: TArray<string>);
    function ChangeSource(out AReason: string): Boolean;
    function InsertTarget(const ADeclarations: TArray<TTransferDeclaration>; const ABodies: TArray<string>;
      out AReason: string): Boolean;
    procedure OverrideSibling(const AHit: TSiblingHit);
  end;

  /// <summary>Ablauf von PushDown mit seinem Zwischenstand.</summary>
  TPushDown = record
    Files: TMemberFiles;
    SourceRef: TMemberClassRef;
    Targets: TArray<TMemberClassRef>;
    Request: TMoveMemberRequest;
    Source: TClassLayout;
    Candidates: TArray<TTransferCandidate>;
    Picked: TArray<Integer>;
    Kept: TArray<Integer>;
    Moved: TArray<Integer>;
    Needed: TArray<Integer>;
    Plan: TMoveMemberPlan;
    function Run(out AReason: string): Boolean;
    /// <summary>Im Vorfahren abstrakt bleiben können nur Methoden, die virtuell werden dürfen.</summary>
    procedure Split;
    function UsersIssue(AId: Integer): string;
    function PlacesIssue(AId: Integer): string;
    /// <summary>Benutzt oben oder fremder Code ein wanderndes Mitglied weiter?</summary>
    function UnusedAbove(out AReason: string): Boolean;
    function OtherUnit: Boolean;
    function MustRaise(AId: Integer; AOtherUnit: Boolean): Boolean;
    procedure AddNeeded(AId: Integer; const AWhy: string);
    /// <summary>Mitglieder, die oben bleiben und unten sichtbar sein müssen.</summary>
    procedure CollectNeeded;
    function AbstractEdits(AId: Integer): TArray<TTextEdit>;
    function ChangeSource(out AReason: string): Boolean;
    function CheckTarget(ATarget: TClassLayout; out AReason: string): Boolean;
    function IsOverrideOf(const AMember: TClassMember; AId: Integer): Boolean;
    /// <summary>Gleichnamige Mitglieder im Nachfahren: Überschreibungen abstrakt bleibender Methoden kommen
    /// nach ASkip, sonst Abbruch.</summary>
    function Overridden(ATarget: TClassLayout; out ASkip: TArray<Integer>; out AReason: string): Boolean;
    function DeclarationOf(AId: Integer): TTransferDeclaration;
    procedure Collect(ATarget: TClassLayout; const ASkip: TArray<Integer>;
      out ADeclarations: TArray<TTransferDeclaration>; out ABodies: TArray<string>);
    function InsertInto(const ARef: TMemberClassRef; out AReason: string): Boolean;
    function InsertAll(out AReason: string): Boolean;
    procedure Finish;
  end;

{ TPullUp }

function TPullUp.Run(out AReason: string): Boolean;
var
  mDeclarations: TArray<TTransferDeclaration>;
  mBodies: TArray<string>;
  mHit: TSiblingHit;
begin
  if Target = nil then
  begin
    Exit(Fail(Format('Der Vorfahr %s ist nicht lesbar.', [TargetRef.ClassName]), AReason));
  end;
  Result := SameGenerics(Source, Target, AReason);
  if Result then
  begin
    Candidates := TMemberTransfer.Candidates(Source);
    Result := Chosen(Candidates, Request.Members, Picked, AReason) and Split(AReason);
  end;
  if not Result then
  begin
    Exit;
  end;
  CompareSiblings;
  RaiseUsed;
  Collect(mDeclarations, mBodies);
  Result := ChangeSource(AReason) and InsertTarget(mDeclarations, mBodies, AReason);
  if Result then
  begin
    for mHit in Hits do
    begin
      OverrideSibling(mHit);
    end;
  end;
end;

function TPullUp.Split(out AReason: string): Boolean;
var
  mId, mIndex: Integer;
  mMissing: TArray<string>;
begin
  Moved := nil;
  Abstracts := nil;
  for mId in Picked do
  begin
    if TMemberTransfer.Has(Request.Abstract, mId) then
    begin
      mIndex := TMemberTransfer.IndexOf(Candidates, mId);
      if not Candidates[mIndex].CanAbstract then
      begin
        Exit(Fail(Format('%s kann nicht abstrakt werden: %s.', [Candidates[mIndex].Name, Candidates[mIndex].Reason]),
          AReason));
      end;
      Abstracts := Abstracts + [mId];
    end
    else
    begin
      Moved := Moved + [mId];
    end;
  end;
  // Was ganz wandert, darf nur benutzen, was mitwandert (abstrakt zählt).
  mMissing := TMemberTransfer.MissingNeeds(Source, Moved, Picked);
  if mMissing <> nil then
  begin
    Exit(Fail(string.Join('; ', mMissing) + '. Bitte mitnehmen oder abstrakt deklarieren.', AReason));
  end;
  for mId in Picked do
  begin
    if Target.Find(Source.Members[mId].Name) <> nil then
    begin
      Exit(Fail(Format('%s hat schon ein Mitglied %s.', [Target.Name, Source.Members[mId].Name]), AReason));
    end;
  end;
  AReason := '';
  Result := True;
end;

procedure TPullUp.CompareSiblings;
var
  mRef: TMemberClassRef;
  mSibling: TClassLayout;
  mTree: TSyntaxTree;
begin
  // Andere Nachfahren des Ziels mit gleichnamigen Methoden.
  Hits := nil;
  Virtualize := nil;
  for mRef in Request.Siblings do
  begin
    if SameText(mRef.ClassName, Source.Name) and SameText(mRef.FileName, SourceRef.FileName) then
    begin
      Continue;
    end;
    mSibling := TMemberTransfer.ParseLayout(Files.Text(mRef.FileName), mRef.ClassName, mTree);
    if mSibling = nil then
    begin
      Continue;
    end;
    try
      CompareSibling(mSibling, mRef);
    finally
      mSibling.Free;
      mTree.Free;
    end;
  end;
end;

procedure TPullUp.CompareSibling(ASibling: TClassLayout; const ARef: TMemberClassRef);
var
  mId, mIndex: Integer;
begin
  for mId in Picked do
  begin
    for mIndex in ASibling.Find(Source.Members[mId].Name) do
    begin
      CompareMethod(ASibling, ARef, mId, mIndex);
    end;
  end;
end;

/// <summary>Methode ohne override?</summary>
function IsPlainMethod(const AMember: TClassMember): Boolean;
begin
  Result := (AMember.Kind = TClassMemberKind.Method) and not AMember.HasDirective('override');
end;

function SameParameters(const AFirst, ASecond: TClassMember): Boolean;
begin
  Result := string.Join(',', AFirst.ParameterTypes) = string.Join(',', ASecond.ParameterTypes);
end;

procedure TPullUp.CompareMethod(ASibling: TClassLayout; const ARef: TMemberClassRef; AId, AIndex: Integer);
var
  mMember, mOther: TClassMember;
  mHit: TSiblingHit;
  mMatched: Boolean;
begin
  mMember := Source.Members[AId];
  mOther := ASibling.Members[AIndex];
  mMatched := IsPlainMethod(mMember) and IsPlainMethod(mOther) and SameParameters(mOther, mMember) and
    (TMemberTransfer.AbstractBlocker(mOther) = '');
  if mMatched and Request.OverrideSiblings then
  begin
    mHit.Ref := ARef;
    mHit.Member := mOther;
    Hits := Hits + [mHit];
    if not TMemberTransfer.Has(Virtualize, AId) then
    begin
      Virtualize := Virtualize + [AId];
    end;
  end
  else if mMatched then
  begin
    Plan.Warnings := Plan.Warnings + [Format('%s.%s verdeckt dann %s.%s (ohne override).',
      [ASibling.Name, mMember.Name, Target.Name, mMember.Name])];
  end
  else
  begin
    Plan.Warnings := Plan.Warnings + [Format('%s.%s passt nicht zu %s.%s und verdeckt es dann.',
      [ASibling.Name, mMember.Name, Target.Name, mMember.Name])];
  end;
end;

procedure TPullUp.RaiseUsed;
var
  mSameUnit: Boolean;
  mId: Integer;
begin
  mSameUnit := SameText(SourceRef.FileName, TargetRef.FileName);
  Raised := nil;
  for mId in Picked do
  begin
    if TMemberTransfer.MustRaise(Source, mId, Moved, TMemberTransfer.Has(Abstracts, mId), mSameUnit, nil) then
    begin
      Raised := Raised + [mId];
      Plan.Raised := Plan.Raised + [Source.Members[mId].Name];
      Plan.Warnings := Plan.Warnings + [Format('%s wird %s, weil %s es weiter benutzt.',
        [Source.Members[mId].Name, TClassEdits.VisibilityName(Request.RaiseVisibility), Source.Name])];
    end;
  end;
end;

function TPullUp.DeclarationOf(AId: Integer): TTransferDeclaration;
var
  mMember: TClassMember;
  mVisibility: TClassVisibility;
  mText: string;
begin
  mMember := Source.Members[AId];
  mVisibility := mMember.Visibility;
  if TMemberTransfer.Has(Raised, AId) then
  begin
    mVisibility := Request.RaiseVisibility;
  end;
  if TMemberTransfer.Has(Abstracts, AId) then
  begin
    mText := TMemberTransfer.WithDoc(Source, AId, TMemberTransfer.AbstractDeclaration(Source, AId));
  end
  else if TMemberTransfer.Has(Virtualize, AId) and not mMember.IsVirtual then
  begin
    mText := TMemberTransfer.WithDoc(Source, AId, TMemberTransfer.VirtualDeclaration(Source, AId));
  end
  else
  begin
    mText := TMemberTransfer.MemberText(Source, AId);
  end;
  Result := TTransferDeclaration.Create(mText, mVisibility,
    mMember.Kind in [TClassMemberKind.Field, TClassMemberKind.ClassVar]);
end;

function TPullUp.BodyOf(AId: Integer): string;
var
  mMember: TClassMember;
begin
  mMember := Source.Members[AId];
  Result := TClassEdits.BodyText(Source, AId, Target.Name);
  if CallsInherited(mMember.Body) and (Source.Ancestors <> nil) and
    not SameText(PlainName(Source.Ancestors[0]), Target.Name) then
  begin
    Plan.Warnings := Plan.Warnings + [Format('%s ruft inherited auf; in %s meint das den Vorfahren von %s.',
      [mMember.Name, Target.Name, Target.Name])];
  end;
end;

procedure TPullUp.Collect(out ADeclarations: TArray<TTransferDeclaration>; out ABodies: TArray<string>);
var
  mId: Integer;
begin
  // Deklarationen und Rümpfe für oben.
  ADeclarations := nil;
  ABodies := nil;
  for mId in Picked do
  begin
    ADeclarations := ADeclarations + [DeclarationOf(mId)];
    if TMemberTransfer.Has(Moved, mId) and (Source.Members[mId].Body <> nil) then
    begin
      ABodies := ABodies + [BodyOf(mId)];
    end;
    if TMemberTransfer.Has(Abstracts, mId) then
    begin
      Plan.Abstracts := Plan.Abstracts + [Source.Members[mId].Name];
    end
    else
    begin
      Plan.Moved := Plan.Moved + [Source.Members[mId].Name];
    end;
  end;
end;

function TPullUp.ChangeSource(out AReason: string): Boolean;
var
  mEdits: TArray<TTextEdit>;
  mOlds: TArray<TClassMember>;
  mText: string;
  mId: Integer;
begin
  // Schritt 1: Klasse ändern.
  mEdits := TClassEdits.DeleteMembers(Source, Moved, True) + TMemberTransfer.EmptiedSections(Source, Moved);
  for mId in Abstracts do
  begin
    mEdits := mEdits + TMemberTransfer.OverrideEdits(Source, Source.Members[mId].Node, True);
  end;
  mText := TTextChanges.Apply(Files.Text(SourceRef.FileName), mEdits);
  mOlds := nil;
  for mId in Abstracts do
  begin
    if TMemberTransfer.Has(Raised, mId) then
    begin
      mOlds := mOlds + [Source.Members[mId]];
    end;
  end;
  AReason := '';
  Result := TMemberTransfer.Relocate(mText, Source.Name, mOlds, Request.RaiseVisibility);
  if Result then
  begin
    Files.Put(SourceRef.FileName, mText);
  end
  else
  begin
    AReason := Format('%s ist nach dem Umbau nicht mehr lesbar.', [Source.Name]);
  end;
end;

function TPullUp.InsertTarget(const ADeclarations: TArray<TTransferDeclaration>; const ABodies: TArray<string>;
  out AReason: string): Boolean;
var
  mText: string;
begin
  // Schritt 2: in den Vorfahren einfügen (gleiche Datei: auf dem neuen Stand).
  mText := Files.Text(TargetRef.FileName);
  Result := TMemberTransfer.InsertInto(mText, Target.Name, ADeclarations, ABodies, AReason);
  if Result then
  begin
    Files.Put(TargetRef.FileName, mText);
  end;
end;

procedure TPullUp.OverrideSibling(const AHit: TSiblingHit);
var
  mText: string;
  mSibling: TClassLayout;
  mTree: TSyntaxTree;
  mIndex: Integer;
begin
  // Schritt 3: andere Nachfahren überschreiben.
  mText := Files.Text(AHit.Ref.FileName);
  mSibling := TMemberTransfer.ParseLayout(mText, AHit.Ref.ClassName, mTree);
  if mSibling = nil then
  begin
    Exit;
  end;
  try
    mIndex := TMemberTransfer.Same(mSibling, AHit.Member);
    if mIndex < 0 then
    begin
      Exit;
    end;
    mText := TTextChanges.Apply(mText, TMemberTransfer.OverrideEdits(mSibling, mSibling.Members[mIndex].Node, True));
    Plan.Overridden := Plan.Overridden + [mSibling.Name + '.' + AHit.Member.Name];
  finally
    mSibling.Free;
    mTree.Free;
  end;
  Files.Put(AHit.Ref.FileName, mText);
end;

{ TPushDown }

function TPushDown.Run(out AReason: string): Boolean;
begin
  Candidates := TMemberTransfer.Candidates(Source);
  Result := Chosen(Candidates, Request.Members, Picked, AReason);
  if not Result then
  begin
    Exit;
  end;
  Split;
  Result := UnusedAbove(AReason);
  if Result then
  begin
    CollectNeeded;
    Result := ChangeSource(AReason) and InsertAll(AReason);
  end;
  if Result then
  begin
    Finish;
  end;
end;

procedure TPushDown.Split;
var
  mId: Integer;
begin
  Kept := nil;
  Moved := nil;
  for mId in Picked do
  begin
    if Request.KeepAbstract and Candidates[TMemberTransfer.IndexOf(Candidates, mId)].CanAbstract then
    begin
      Kept := Kept + [mId];
    end
    else
    begin
      Moved := Moved + [mId];
    end;
  end;
end;

function TPushDown.UsersIssue(AId: Integer): string;
var
  mUser: Integer;
  mUsers: TArray<string>;
begin
  Result := '';
  mUsers := nil;
  for mUser in Source.UsersOf(AId) do
  begin
    if not TMemberTransfer.Has(Picked, mUser) then
    begin
      mUsers := mUsers + [Source.Members[mUser].Name];
    end;
  end;
  if mUsers <> nil then
  begin
    Result := Format('%s wird in %s weiter benutzt (%s).', [Source.Members[AId].Name, Source.Name,
      string.Join(', ', mUsers)]);
  end;
end;

function TPushDown.PlacesIssue(AId: Integer): string;
var
  mUsage: TMemberUsage;
  mPlaces: TArray<string>;
begin
  Result := '';
  mPlaces := nil;
  for mUsage in Request.Usages do
  begin
    if (mUsage.Id = AId) and (Length(mPlaces) < 5) then
    begin
      mPlaces := mPlaces + [mUsage.Where];
    end;
  end;
  if mPlaces <> nil then
  begin
    Result := Format('%s wird außerhalb der Nachfahren über %s benutzt: %s.', [Source.Members[AId].Name,
      Source.Name, string.Join(', ', mPlaces)]);
  end;
end;

function TPushDown.UnusedAbove(out AReason: string): Boolean;
var
  mId: Integer;
begin
  AReason := '';
  for mId in Moved do
  begin
    AReason := UsersIssue(mId);
    if AReason = '' then
    begin
      AReason := PlacesIssue(mId);
    end;
    if AReason <> '' then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TPushDown.OtherUnit: Boolean;
var
  mRef: TMemberClassRef;
begin
  Result := False;
  for mRef in Targets do
  begin
    if not SameText(mRef.FileName, SourceRef.FileName) then
    begin
      Result := True;
    end;
  end;
end;

function TPushDown.MustRaise(AId: Integer; AOtherUnit: Boolean): Boolean;
begin
  Result := (Source.Members[AId].Visibility = TClassVisibility.StrictPrivate) or
    ((Source.Members[AId].Visibility = TClassVisibility.Private_) and AOtherUnit);
end;

procedure TPushDown.AddNeeded(AId: Integer; const AWhy: string);
begin
  Needed := Needed + [AId];
  Plan.Raised := Plan.Raised + [Source.Members[AId].Name];
  Plan.Warnings := Plan.Warnings + [Format('%s wird %s, %s', [Source.Members[AId].Name,
    TClassEdits.VisibilityName(Request.RaiseVisibility), AWhy])];
end;

procedure TPushDown.CollectNeeded;
var
  mOtherUnit: Boolean;
  mId, mNeed: Integer;
begin
  mOtherUnit := OtherUnit;
  Needed := nil;
  for mId in Moved do
  begin
    for mNeed in Source.UsedBy(mId) do
    begin
      if not TMemberTransfer.Has(Picked, mNeed) and not TMemberTransfer.Has(Needed, mNeed) and
        MustRaise(mNeed, mOtherUnit) and (Source.Members[mNeed].Kind <> TClassMemberKind.Other) then
      begin
        AddNeeded(mNeed, 'weil die Nachfahren es benutzen.');
      end;
    end;
  end;
  // Abstrakt bleibende Methoden müssen die Nachfahren überschreiben können.
  for mId in Kept do
  begin
    if MustRaise(mId, mOtherUnit) then
    begin
      AddNeeded(mId, 'damit die Nachfahren es überschreiben können.');
    end;
  end;
end;

function TPushDown.AbstractEdits(AId: Integer): TArray<TTextEdit>;
var
  mMember: TClassMember;
begin
  mMember := Source.Members[AId];
  Result := nil;
  Result := Result + [TTextEdit.Create(TTextRange.Create(mMember.Node.StartPos, mMember.Node.EndPos),
    TMemberTransfer.AbstractDeclaration(Source, AId))];
  if mMember.Body <> nil then
  begin
    Result := Result + [TClassEdits.DeleteLines(Source, mMember.BodyFirstLine, mMember.BodyLastLine)];
  end;
end;

function TPushDown.ChangeSource(out AReason: string): Boolean;
var
  mEdits: TArray<TTextEdit>;
  mOlds: TArray<TClassMember>;
  mText: string;
  mId: Integer;
begin
  // Schritt 1: Vorfahr ändern.
  mEdits := TClassEdits.DeleteMembers(Source, Moved, True) + TMemberTransfer.EmptiedSections(Source, Moved);
  for mId in Kept do
  begin
    mEdits := mEdits + AbstractEdits(mId);
  end;
  mText := TTextChanges.Apply(Files.Text(SourceRef.FileName), mEdits);
  mOlds := nil;
  for mId in Needed do
  begin
    mOlds := mOlds + [Source.Members[mId]];
  end;
  AReason := '';
  Result := TMemberTransfer.Relocate(mText, Source.Name, mOlds, Request.RaiseVisibility);
  if Result then
  begin
    Files.Put(SourceRef.FileName, mText);
  end
  else
  begin
    AReason := Format('%s ist nach dem Umbau nicht mehr lesbar.', [Source.Name]);
  end;
end;

function TPushDown.CheckTarget(ATarget: TClassLayout; out AReason: string): Boolean;
begin
  if (ATarget.Ancestors = nil) or not SameText(PlainName(ATarget.Ancestors[0]), Source.Name) then
  begin
    Exit(Fail(Format('%s ist kein direkter Nachfahr von %s.', [ATarget.Name, Source.Name]), AReason));
  end;
  Result := SameGenerics(Source, ATarget, AReason);
end;

function TPushDown.IsOverrideOf(const AMember: TClassMember; AId: Integer): Boolean;
begin
  Result := TMemberTransfer.Has(Kept, AId) and (AMember.Kind = TClassMemberKind.Method) and
    AMember.HasDirective('override') and SameParameters(AMember, Source.Members[AId]);
end;

function TPushDown.Overridden(ATarget: TClassLayout; out ASkip: TArray<Integer>; out AReason: string): Boolean;
var
  mId, mFound: Integer;
begin
  ASkip := nil;
  AReason := '';
  for mId in Picked do
  begin
    for mFound in ATarget.Find(Source.Members[mId].Name) do
    begin
      if not IsOverrideOf(ATarget.Members[mFound], mId) then
      begin
        Exit(Fail(Format('%s hat schon ein Mitglied %s.', [ATarget.Name, Source.Members[mId].Name]), AReason));
      end;
      ASkip := ASkip + [mId];
    end;
  end;
  Result := True;
end;

function TPushDown.DeclarationOf(AId: Integer): TTransferDeclaration;
var
  mMember: TClassMember;
  mVisibility: TClassVisibility;
  mText: string;
begin
  mMember := Source.Members[AId];
  mVisibility := mMember.Visibility;
  if TMemberTransfer.Has(Needed, AId) then
  begin
    mVisibility := Request.RaiseVisibility;
  end;
  if TMemberTransfer.Has(Kept, AId) then
  begin
    mText := TMemberTransfer.WithDoc(Source, AId, TMemberTransfer.OverrideDeclaration(Source, AId));
  end
  else
  begin
    mText := TMemberTransfer.MemberText(Source, AId);
  end;
  Result := TTransferDeclaration.Create(mText, mVisibility,
    mMember.Kind in [TClassMemberKind.Field, TClassMemberKind.ClassVar]);
end;

procedure TPushDown.Collect(ATarget: TClassLayout; const ASkip: TArray<Integer>;
  out ADeclarations: TArray<TTransferDeclaration>; out ABodies: TArray<string>);
var
  mId: Integer;
begin
  ADeclarations := nil;
  ABodies := nil;
  for mId in Picked do
  begin
    if TMemberTransfer.Has(ASkip, mId) then
    begin
      Continue;
    end;
    ADeclarations := ADeclarations + [DeclarationOf(mId)];
    if Source.Members[mId].Body <> nil then
    begin
      ABodies := ABodies + [TClassEdits.BodyText(Source, mId, ATarget.Name)];
    end;
  end;
end;

function TPushDown.InsertInto(const ARef: TMemberClassRef; out AReason: string): Boolean;
var
  mTarget: TClassLayout;
  mTree: TSyntaxTree;
  mSkip: TArray<Integer>;
  mDeclarations: TArray<TTransferDeclaration>;
  mBodies: TArray<string>;
  mText: string;
begin
  mTarget := TMemberTransfer.ParseLayout(Files.Text(ARef.FileName), ARef.ClassName, mTree);
  if mTarget = nil then
  begin
    Exit(Fail(Format('Der Nachfahr %s ist nicht lesbar.', [ARef.ClassName]), AReason));
  end;
  try
    Result := CheckTarget(mTarget, AReason) and Overridden(mTarget, mSkip, AReason);
    if Result then
    begin
      Collect(mTarget, mSkip, mDeclarations, mBodies);
      mText := Files.Text(ARef.FileName);
      Result := TMemberTransfer.InsertInto(mText, mTarget.Name, mDeclarations, mBodies, AReason);
      if Result then
      begin
        Files.Put(ARef.FileName, mText);
      end;
    end;
  finally
    mTarget.Free;
    mTree.Free;
  end;
end;

function TPushDown.InsertAll(out AReason: string): Boolean;
var
  mRef: TMemberClassRef;
begin
  // Schritt 2: in jeden Nachfahren einfügen.
  AReason := '';
  for mRef in Targets do
  begin
    if not InsertInto(mRef, AReason) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

procedure TPushDown.Finish;
var
  mId: Integer;
begin
  for mId in Picked do
  begin
    if TMemberTransfer.Has(Kept, mId) then
    begin
      Plan.Abstracts := Plan.Abstracts + [Source.Members[mId].Name];
    end
    else
    begin
      Plan.Moved := Plan.Moved + [Source.Members[mId].Name];
    end;
  end;
  if (Kept <> nil) and (Request.AllTargets > Length(Targets)) then
  begin
    Plan.Warnings := Plan.Warnings + [Format('Die übrigen Nachfahren von %s müssen %s selbst überschreiben ' +
      '(sonst EAbstractError).', [Source.Name, string.Join(', ', Plan.Abstracts)])];
  end;
end;

{ TMoveMember: Verschieben }

class function TMoveMember.PullUp(AFiles: TMemberFiles; const ASource, ATarget: TMemberClassRef;
  const ARequest: TMoveMemberRequest; out APlan: TMoveMemberPlan; out AReason: string): Boolean;
var
  mWork: TPullUp;
  mSourceTree, mTargetTree: TSyntaxTree;
begin
  APlan := Default(TMoveMemberPlan);
  AReason := '';
  mWork := Default(TPullUp);
  mWork.Files := AFiles;
  mWork.SourceRef := ASource;
  mWork.TargetRef := ATarget;
  mWork.Request := ARequest;
  mWork.Source := TMemberTransfer.ParseLayout(AFiles.Text(ASource.FileName), ASource.ClassName, mSourceTree);
  if mWork.Source = nil then
  begin
    Exit(Fail(Format('%s ist nicht lesbar.', [ASource.ClassName]), AReason));
  end;
  mTargetTree := nil;
  try
    mWork.Target := TMemberTransfer.ParseLayout(AFiles.Text(ATarget.FileName), ATarget.ClassName, mTargetTree);
    Result := mWork.Run(AReason);
    APlan := mWork.Plan;
  finally
    mWork.Target.Free;
    mTargetTree.Free;
    mWork.Source.Free;
    mSourceTree.Free;
  end;
end;

class function TMoveMember.PushDown(AFiles: TMemberFiles; const ASource: TMemberClassRef;
  const ATargets: TArray<TMemberClassRef>; const ARequest: TMoveMemberRequest; out APlan: TMoveMemberPlan;
  out AReason: string): Boolean;
var
  mWork: TPushDown;
  mSourceTree: TSyntaxTree;
begin
  APlan := Default(TMoveMemberPlan);
  AReason := '';
  if ATargets = nil then
  begin
    Exit(Fail('Bitte mindestens einen Nachfahren wählen.', AReason));
  end;
  mWork := Default(TPushDown);
  mWork.Files := AFiles;
  mWork.SourceRef := ASource;
  mWork.Targets := ATargets;
  mWork.Request := ARequest;
  mWork.Source := TMemberTransfer.ParseLayout(AFiles.Text(ASource.FileName), ASource.ClassName, mSourceTree);
  if mWork.Source = nil then
  begin
    Exit(Fail(Format('%s ist nicht lesbar.', [ASource.ClassName]), AReason));
  end;
  try
    Result := mWork.Run(AReason);
    APlan := mWork.Plan;
  finally
    mWork.Source.Free;
    mSourceTree.Free;
  end;
end;

end.
