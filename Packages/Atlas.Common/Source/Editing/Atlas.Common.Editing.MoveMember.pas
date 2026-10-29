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
    Result := Trim(Copy(Result, 1, Pos('<', Result) - 1));
end;

/// <summary>Ruft der Rumpf inherited auf?</summary>
function CallsInherited(ABody: TSyntaxNode): Boolean;
var
  Found: Boolean;
begin
  if ABody = nil then
    Exit(False);
  Found := False;
  ABody.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.InheritedExpr then
        Found := True;
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
    Exit(Fail('Bitte mindestens ein Mitglied wählen.', AReason));
  for Id in AIds do
  begin
    Index := TMemberTransfer.IndexOf(ACandidates, Id);
    if Index < 0 then
      Exit(Fail(Format('Mitglied %d ist kein Kandidat.', [Id]), AReason));
    if not ACandidates[Index].Enabled then
      Exit(Fail(Format('%s kann nicht wandern: %s.', [ACandidates[Index].Name, ACandidates[Index].Reason]), AReason));
    if not TMemberTransfer.Has(AChosen, Id) then
      AChosen := AChosen + [Id];
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
    if SameText(FNames[Index], AFileName) then
      Exit(Index);
  Result := -1;
end;

procedure TMemberFiles.Add(const AFileName, AText: string);
begin
  if IndexOf(AFileName) >= 0 then
    Exit;
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
    Exit('');
  Result := FTexts[Index];
end;

procedure TMemberFiles.Put(const AFileName, AText: string);
var
  Index: Integer;
begin
  Index := IndexOf(AFileName);
  if Index < 0 then
    Add(AFileName, AText)
  else
    FTexts[Index] := AText;
end;

function TMemberFiles.Original(const AFileName: string): string;
var
  Index: Integer;
begin
  Index := IndexOf(AFileName);
  if Index < 0 then
    Exit('');
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
    Exit(Fail('An dieser Stelle steht keine Klasse.', AReason));
  Layout := TClassLayout.Read(ATree, AText, Decl);
  try
    AInfo.ClassName := Layout.Name;
    if Layout.Ancestors <> nil then
      AInfo.Ancestor := Layout.Ancestors[0];
    AInfo.Candidates := TMemberTransfer.Candidates(Layout);
    Member := Layout.MemberAtLine(ALine);
    if (Member < 0) or (TMemberTransfer.IndexOf(AInfo.Candidates, Member) < 0) then
      Exit(Fail('An dieser Stelle steht kein Feld, keine Methode und keine Property.', AReason));
    if not AInfo.Candidates[TMemberTransfer.IndexOf(AInfo.Candidates, Member)].Enabled then
      Exit(Fail(Format('%s kann nicht wandern: %s.', [Layout.Members[Member].Name,
        AInfo.Candidates[TMemberTransfer.IndexOf(AInfo.Candidates, Member)].Reason]), AReason));
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
    AReason := Format('%s und %s haben verschiedene Typparameter; Rümpfe ließen sich nicht übertragen.',
      [ASource.Name, ATarget.Name]);
end;

class function TMoveMember.PullUp(AFiles: TMemberFiles; const ASource, ATarget: TMemberClassRef;
  const ARequest: TMoveMemberRequest; out APlan: TMoveMemberPlan; out AReason: string): Boolean;
type
  TSiblingHit = record
    Ref: TMemberClassRef;
    Member: TClassMember;
  end;
var
  Source, Target, Sibling: TClassLayout;
  SourceTree, TargetTree, SiblingTree: TSyntaxTree;
  Candidates: TArray<TTransferCandidate>;
  Picked, Moved, Abstracts, Virtualize, Raised: TArray<Integer>;
  Missing: TArray<string>;
  Id, Index: Integer;
  Member: TClassMember;
  Ref: TMemberClassRef;
  Hits: TArray<TSiblingHit>;
  Hit: TSiblingHit;
  Visibility: TClassVisibility;
  Declarations: TArray<TTransferDeclaration>;
  Bodies: TArray<string>;
  Olds: TArray<TClassMember>;
  Edits: TArray<TTextEdit>;
  Text, Declaration: string;
  SameUnit, Matched: Boolean;
begin
  APlan := Default(TMoveMemberPlan);
  AReason := '';
  Source := TMemberTransfer.ParseLayout(AFiles.Text(ASource.FileName), ASource.ClassName, SourceTree);
  if Source = nil then
    Exit(Fail(Format('%s ist nicht lesbar.', [ASource.ClassName]), AReason));
  Target := nil;
  TargetTree := nil;
  try
    Target := TMemberTransfer.ParseLayout(AFiles.Text(ATarget.FileName), ATarget.ClassName, TargetTree);
    if Target = nil then
      Exit(Fail(Format('Der Vorfahr %s ist nicht lesbar.', [ATarget.ClassName]), AReason));
    if not SameGenerics(Source, Target, AReason) then
      Exit(False);
    Candidates := TMemberTransfer.Candidates(Source);
    if not Chosen(Candidates, ARequest.Members, Picked, AReason) then
      Exit(False);
    Moved := nil;
    Abstracts := nil;
    for Id in Picked do
      if TMemberTransfer.Has(ARequest.Abstract, Id) then
      begin
        Index := TMemberTransfer.IndexOf(Candidates, Id);
        if not Candidates[Index].CanAbstract then
          Exit(Fail(Format('%s kann nicht abstrakt werden: %s.', [Candidates[Index].Name, Candidates[Index].Reason]),
            AReason));
        Abstracts := Abstracts + [Id];
      end
      else
        Moved := Moved + [Id];
    // Was ganz wandert, darf nur benutzen, was mitwandert (abstrakt zählt).
    Missing := TMemberTransfer.MissingNeeds(Source, Moved, Picked);
    if Missing <> nil then
      Exit(Fail(string.Join('; ', Missing) + '. Bitte mitnehmen oder abstrakt deklarieren.', AReason));
    for Id in Picked do
      if Target.Find(Source.Members[Id].Name) <> nil then
        Exit(Fail(Format('%s hat schon ein Mitglied %s.', [Target.Name, Source.Members[Id].Name]), AReason));
    // Andere Nachfahren des Ziels mit gleichnamigen Methoden.
    Hits := nil;
    Virtualize := nil;
    for Ref in ARequest.Siblings do
    begin
      if SameText(Ref.ClassName, Source.Name) and SameText(Ref.FileName, ASource.FileName) then
        Continue;
      Sibling := TMemberTransfer.ParseLayout(AFiles.Text(Ref.FileName), Ref.ClassName, SiblingTree);
      if Sibling = nil then
        Continue;
      try
        for Id in Picked do
        begin
          Member := Source.Members[Id];
          for Index in Sibling.Find(Member.Name) do
          begin
            Matched := (Member.Kind = TClassMemberKind.Method) and
              (Sibling.Members[Index].Kind = TClassMemberKind.Method) and
              (string.Join(',', Sibling.Members[Index].ParameterTypes) = string.Join(',', Member.ParameterTypes)) and
              not Member.HasDirective('override') and not Sibling.Members[Index].HasDirective('override') and
              (TMemberTransfer.AbstractBlocker(Sibling.Members[Index]) = '');
            if Matched and ARequest.OverrideSiblings then
            begin
              Hit.Ref := Ref;
              Hit.Member := Sibling.Members[Index];
              Hits := Hits + [Hit];
              if not TMemberTransfer.Has(Virtualize, Id) then
                Virtualize := Virtualize + [Id];
            end
            else if Matched then
              APlan.Warnings := APlan.Warnings + [Format('%s.%s verdeckt dann %s.%s (ohne override).',
                [Sibling.Name, Member.Name, Target.Name, Member.Name])]
            else
              APlan.Warnings := APlan.Warnings + [Format('%s.%s passt nicht zu %s.%s und verdeckt es dann.',
                [Sibling.Name, Member.Name, Target.Name, Member.Name])];
          end;
        end;
      finally
        Sibling.Free;
        SiblingTree.Free;
      end;
    end;
    // Sichtbarkeit oben; gehobene abstrakte Methoden unten in denselben Abschnitt (sonst H2269).
    SameUnit := SameText(ASource.FileName, ATarget.FileName);
    Raised := nil;
    for Id in Picked do
      if TMemberTransfer.MustRaise(Source, Id, Moved, TMemberTransfer.Has(Abstracts, Id), SameUnit, nil) then
      begin
        Raised := Raised + [Id];
        APlan.Raised := APlan.Raised + [Source.Members[Id].Name];
        APlan.Warnings := APlan.Warnings + [Format('%s wird %s, weil %s es weiter benutzt.',
          [Source.Members[Id].Name, TClassEdits.VisibilityName(ARequest.RaiseVisibility), Source.Name])];
      end;
    // Deklarationen und Rümpfe für oben.
    Declarations := nil;
    Bodies := nil;
    for Id in Picked do
    begin
      Member := Source.Members[Id];
      Visibility := Member.Visibility;
      if TMemberTransfer.Has(Raised, Id) then
        Visibility := ARequest.RaiseVisibility;
      if TMemberTransfer.Has(Abstracts, Id) then
        Declaration := TMemberTransfer.WithDoc(Source, Id, TMemberTransfer.AbstractDeclaration(Source, Id))
      else if TMemberTransfer.Has(Virtualize, Id) and not Member.IsVirtual then
        Declaration := TMemberTransfer.WithDoc(Source, Id, TMemberTransfer.VirtualDeclaration(Source, Id))
      else
        Declaration := TMemberTransfer.MemberText(Source, Id);
      Declarations := Declarations + [TTransferDeclaration.Create(Declaration, Visibility,
        Member.Kind in [TClassMemberKind.Field, TClassMemberKind.ClassVar])];
      if TMemberTransfer.Has(Moved, Id) and (Member.Body <> nil) then
      begin
        Bodies := Bodies + [TClassEdits.BodyText(Source, Id, Target.Name)];
        if CallsInherited(Member.Body) and (Source.Ancestors <> nil) and
          not SameText(PlainName(Source.Ancestors[0]), Target.Name) then
          APlan.Warnings := APlan.Warnings + [Format('%s ruft inherited auf; in %s meint das den Vorfahren von %s.',
            [Member.Name, Target.Name, Target.Name])];
      end;
      if TMemberTransfer.Has(Abstracts, Id) then
        APlan.Abstracts := APlan.Abstracts + [Member.Name]
      else
        APlan.Moved := APlan.Moved + [Member.Name];
    end;
    // Schritt 1: Klasse ändern.
    Edits := TClassEdits.DeleteMembers(Source, Moved, True) + TMemberTransfer.EmptiedSections(Source, Moved);
    for Id in Abstracts do
      Edits := Edits + TMemberTransfer.OverrideEdits(Source, Source.Members[Id].Node, True);
    Text := TTextChanges.Apply(AFiles.Text(ASource.FileName), Edits);
    Olds := nil;
    for Id in Abstracts do
      if TMemberTransfer.Has(Raised, Id) then
        Olds := Olds + [Source.Members[Id]];
    if not TMemberTransfer.Relocate(Text, Source.Name, Olds, ARequest.RaiseVisibility) then
      Exit(Fail(Format('%s ist nach dem Umbau nicht mehr lesbar.', [Source.Name]), AReason));
    AFiles.Put(ASource.FileName, Text);
    // Schritt 2: in den Vorfahren einfügen (gleiche Datei: auf dem neuen Stand).
    Text := AFiles.Text(ATarget.FileName);
    if not TMemberTransfer.InsertInto(Text, Target.Name, Declarations, Bodies, AReason) then
      Exit(False);
    AFiles.Put(ATarget.FileName, Text);
    // Schritt 3: andere Nachfahren überschreiben.
    for Hit in Hits do
    begin
      Text := AFiles.Text(Hit.Ref.FileName);
      Sibling := TMemberTransfer.ParseLayout(Text, Hit.Ref.ClassName, SiblingTree);
      if Sibling = nil then
        Continue;
      try
        Index := TMemberTransfer.Same(Sibling, Hit.Member);
        if Index < 0 then
          Continue;
        Text := TTextChanges.Apply(Text, TMemberTransfer.OverrideEdits(Sibling, Sibling.Members[Index].Node, True));
        APlan.Overridden := APlan.Overridden + [Sibling.Name + '.' + Hit.Member.Name];
      finally
        Sibling.Free;
        SiblingTree.Free;
      end;
      AFiles.Put(Hit.Ref.FileName, Text);
    end;
  finally
    Target.Free;
    TargetTree.Free;
    Source.Free;
    SourceTree.Free;
  end;
  Result := True;
end;

class function TMoveMember.PushDown(AFiles: TMemberFiles; const ASource: TMemberClassRef;
  const ATargets: TArray<TMemberClassRef>; const ARequest: TMoveMemberRequest; out APlan: TMoveMemberPlan;
  out AReason: string): Boolean;
var
  Source, Target: TClassLayout;
  SourceTree, TargetTree: TSyntaxTree;
  Candidates: TArray<TTransferCandidate>;
  Picked, Kept, Moved, Needed, Skip: TArray<Integer>;
  Id, Need, User, Found: Integer;
  Member: TClassMember;
  Visibility: TClassVisibility;
  Ref: TMemberClassRef;
  Usage: TMemberUsage;
  Places, Users: TArray<string>;
  OtherUnit, Raise_: Boolean;
  Edits: TArray<TTextEdit>;
  Olds: TArray<TClassMember>;
  Declarations: TArray<TTransferDeclaration>;
  Bodies: TArray<string>;
  Text, Declaration: string;
begin
  APlan := Default(TMoveMemberPlan);
  AReason := '';
  if ATargets = nil then
    Exit(Fail('Bitte mindestens einen Nachfahren wählen.', AReason));
  Source := TMemberTransfer.ParseLayout(AFiles.Text(ASource.FileName), ASource.ClassName, SourceTree);
  if Source = nil then
    Exit(Fail(Format('%s ist nicht lesbar.', [ASource.ClassName]), AReason));
  try
    Candidates := TMemberTransfer.Candidates(Source);
    if not Chosen(Candidates, ARequest.Members, Picked, AReason) then
      Exit(False);
    // Im Vorfahren abstrakt bleiben können nur Methoden, die virtuell werden dürfen.
    Kept := nil;
    Moved := nil;
    for Id in Picked do
      if ARequest.KeepAbstract and Candidates[TMemberTransfer.IndexOf(Candidates, Id)].CanAbstract then
        Kept := Kept + [Id]
      else
        Moved := Moved + [Id];
    // Wer das Mitglied oben weiter benutzt.
    for Id in Moved do
    begin
      Users := nil;
      for User in Source.UsersOf(Id) do
        if not TMemberTransfer.Has(Picked, User) then
          Users := Users + [Source.Members[User].Name];
      if Users <> nil then
        Exit(Fail(Format('%s wird in %s weiter benutzt (%s).', [Source.Members[Id].Name, Source.Name,
          string.Join(', ', Users)]), AReason));
      Places := nil;
      for Usage in ARequest.Usages do
        if (Usage.Id = Id) and (Length(Places) < 5) then
          Places := Places + [Usage.Where];
      if Places <> nil then
        Exit(Fail(Format('%s wird außerhalb der Nachfahren über %s benutzt: %s.', [Source.Members[Id].Name,
          Source.Name, string.Join(', ', Places)]), AReason));
    end;
    // Mitglieder, die oben bleiben und unten sichtbar sein müssen.
    OtherUnit := False;
    for Ref in ATargets do
      if not SameText(Ref.FileName, ASource.FileName) then
        OtherUnit := True;
    Needed := nil;
    for Id in Moved do
      for Need in Source.UsedBy(Id) do
        if not TMemberTransfer.Has(Picked, Need) and not TMemberTransfer.Has(Needed, Need) then
        begin
          Raise_ := (Source.Members[Need].Visibility = TClassVisibility.StrictPrivate) or
            ((Source.Members[Need].Visibility = TClassVisibility.Private_) and OtherUnit);
          if Raise_ and (Source.Members[Need].Kind <> TClassMemberKind.Other) then
          begin
            Needed := Needed + [Need];
            APlan.Raised := APlan.Raised + [Source.Members[Need].Name];
            APlan.Warnings := APlan.Warnings + [Format('%s wird %s, weil die Nachfahren es benutzen.',
              [Source.Members[Need].Name, TClassEdits.VisibilityName(ARequest.RaiseVisibility)])];
          end;
        end;
    // Abstrakt bleibende Methoden müssen die Nachfahren überschreiben können.
    for Id in Kept do
    begin
      Raise_ := (Source.Members[Id].Visibility = TClassVisibility.StrictPrivate) or
        ((Source.Members[Id].Visibility = TClassVisibility.Private_) and OtherUnit);
      if Raise_ then
      begin
        Needed := Needed + [Id];
        APlan.Raised := APlan.Raised + [Source.Members[Id].Name];
        APlan.Warnings := APlan.Warnings + [Format('%s wird %s, damit die Nachfahren es überschreiben können.',
          [Source.Members[Id].Name, TClassEdits.VisibilityName(ARequest.RaiseVisibility)])];
      end;
    end;
    // Schritt 1: Vorfahr ändern.
    Edits := TClassEdits.DeleteMembers(Source, Moved, True) + TMemberTransfer.EmptiedSections(Source, Moved);
    for Id in Kept do
    begin
      Member := Source.Members[Id];
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Member.Node.StartPos, Member.Node.EndPos),
        TMemberTransfer.AbstractDeclaration(Source, Id))];
      if Member.Body <> nil then
        Edits := Edits + [TClassEdits.DeleteLines(Source, Member.BodyFirstLine, Member.BodyLastLine)];
    end;
    Text := TTextChanges.Apply(AFiles.Text(ASource.FileName), Edits);
    Olds := nil;
    for Need in Needed do
      Olds := Olds + [Source.Members[Need]];
    if not TMemberTransfer.Relocate(Text, Source.Name, Olds, ARequest.RaiseVisibility) then
      Exit(Fail(Format('%s ist nach dem Umbau nicht mehr lesbar.', [Source.Name]), AReason));
    AFiles.Put(ASource.FileName, Text);
    // Schritt 2: in jeden Nachfahren einfügen.
    for Ref in ATargets do
    begin
      Target := TMemberTransfer.ParseLayout(AFiles.Text(Ref.FileName), Ref.ClassName, TargetTree);
      if Target = nil then
        Exit(Fail(Format('Der Nachfahr %s ist nicht lesbar.', [Ref.ClassName]), AReason));
      try
        if (Target.Ancestors = nil) or not SameText(PlainName(Target.Ancestors[0]), Source.Name) then
          Exit(Fail(Format('%s ist kein direkter Nachfahr von %s.', [Target.Name, Source.Name]), AReason));
        if not SameGenerics(Source, Target, AReason) then
          Exit(False);
        Skip := nil;
        for Id in Picked do
          for Found in Target.Find(Source.Members[Id].Name) do
            if TMemberTransfer.Has(Kept, Id) and (Target.Members[Found].Kind = TClassMemberKind.Method) and
              Target.Members[Found].HasDirective('override') and (string.Join(',',
              Target.Members[Found].ParameterTypes) = string.Join(',', Source.Members[Id].ParameterTypes)) then
              Skip := Skip + [Id]
            else
              Exit(Fail(Format('%s hat schon ein Mitglied %s.', [Target.Name, Source.Members[Id].Name]), AReason));
        Declarations := nil;
        Bodies := nil;
        for Id in Picked do
        begin
          if TMemberTransfer.Has(Skip, Id) then
            Continue;
          Member := Source.Members[Id];
          Visibility := Member.Visibility;
          if TMemberTransfer.Has(Needed, Id) then
            Visibility := ARequest.RaiseVisibility;
          if TMemberTransfer.Has(Kept, Id) then
            Declaration := TMemberTransfer.WithDoc(Source, Id, TMemberTransfer.OverrideDeclaration(Source, Id))
          else
            Declaration := TMemberTransfer.MemberText(Source, Id);
          Declarations := Declarations + [TTransferDeclaration.Create(Declaration, Visibility,
            Member.Kind in [TClassMemberKind.Field, TClassMemberKind.ClassVar])];
          if Member.Body <> nil then
            Bodies := Bodies + [TClassEdits.BodyText(Source, Id, Target.Name)];
        end;
        Text := AFiles.Text(Ref.FileName);
        if not TMemberTransfer.InsertInto(Text, Target.Name, Declarations, Bodies, AReason) then
          Exit(False);
        AFiles.Put(Ref.FileName, Text);
      finally
        Target.Free;
        TargetTree.Free;
      end;
    end;
    for Id in Picked do
      if TMemberTransfer.Has(Kept, Id) then
        APlan.Abstracts := APlan.Abstracts + [Source.Members[Id].Name]
      else
        APlan.Moved := APlan.Moved + [Source.Members[Id].Name];
    if (Kept <> nil) and (ARequest.AllTargets > Length(ATargets)) then
      APlan.Warnings := APlan.Warnings + [Format('Die übrigen Nachfahren von %s müssen %s selbst überschreiben ' +
        '(sonst EAbstractError).', [Source.Name, string.Join(', ', APlan.Abstracts)])];
  finally
    Source.Free;
    SourceTree.Free;
  end;
  Result := True;
end;

end.
