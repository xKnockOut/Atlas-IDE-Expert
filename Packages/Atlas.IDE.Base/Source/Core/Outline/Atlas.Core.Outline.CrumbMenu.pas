unit Atlas.Core.Outline.CrumbMenu;

// Rechtsklick-Menü an den Gliedern der Brotkrumenleiste (#1786), Kern ohne
// VCL und OTA:
// - ActionsOf nennt die Einträge, die zum Glied passen: beim Unit-Glied
//   Unit-Namen und Dateipfad kopieren, bei Gliedern mit Knoten Namen, Namen
//   mit Unit und (bei Routinen) Signatur kopieren, Verwendungen suchen,
//   Umbenennen und, wenn MemberOf einen Namen liefert, die Komponente im
//   Designer. Den Pfad der Leiste kopieren geht immer. Schlüsselwort-Glieder
//   (Abschnitt, Block, Region, Bedingung, try/case) haben nur den Pfad.
// - SignatureOf liest den Kopf der Routine aus dem Text bis zum Semikolon
//   hinter der Parameterliste, Leerraum zusammengezogen; ohne Rumpf mit dem
//   Besitzer vor dem Namen („procedure TKunde.Laden(const AName: string)“).
// - ComponentOf sucht im Formulartext (.dfm/.fmx als Text) die Komponente zu
//   einem Mitglied: ein Komponentenfeld heißt wie seine Komponente, ein
//   Ereignisbehandler steht als „OnClick = btnSpeichernClick“ in ihr. Ein
//   Ereignis des Formulars selbst liefert das Formular.

interface

uses
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs;

type
{$SCOPEDENUMS ON}
  TAtlasCrumbAction = (CopyName, CopyWithUnit, CopySignature, CopyPath, ShowComponent, FindReferences, Rename,
    CopyUnitName, CopyFilePath);
{$SCOPEDENUMS OFF}
  TAtlasCrumbActions = set of TAtlasCrumbAction;

  TAtlasCrumbMenu = class
  public
    /// <summary>Einträge für das Glied ACrumb; ShowComponent nur mit AHasComponent.</summary>
    class function ActionsOf(const ANodes: TAtlasOutlineNodes; const ACrumb: TAtlasCrumb;
      AHasComponent: Boolean): TAtlasCrumbActions; static;
    /// <summary>Name mit Besitzer („TKunde.Laden“).</summary>
    class function NameOf(const ANodes: TAtlasOutlineNodes; ANode: Integer): string; static;
    /// <summary>Kopf der Routine ohne Semikolon und Direktiven; '' ohne Routine.</summary>
    class function SignatureOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      ANode: Integer): string; static;
    /// <summary>Texte aller Glieder mit „ › “ dazwischen.</summary>
    class function PathOf(const ACrumbs: TAtlasCrumbs): string; static;
    /// <summary>Name, unter dem das Mitglied im Formular stehen kann (Feld oder Methode eines Typs); ''
    /// sonst.</summary>
    class function MemberOf(const ANodes: TAtlasOutlineNodes; ANode: Integer): string; static;
    /// <summary>Komponente zum Mitglied AMember im Formulartext AFormText; '' ohne.</summary>
    class function ComponentOf(const AFormText, AMember: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Forms.Changes;

function IsRoutine(const ANode: TAtlasOutlineNode): Boolean;
begin
  Result := ANode.Category in [TAtlasOutlineCategory.Method, TAtlasOutlineCategory.Routine];
end;

function ValidNode(const ANodes: TAtlasOutlineNodes; ANode: Integer): Boolean;
begin
  Result := (ANode >= 0) and (ANode <= High(ANodes));
end;

class function TAtlasCrumbMenu.ActionsOf(const ANodes: TAtlasOutlineNodes; const ACrumb: TAtlasCrumb;
  AHasComponent: Boolean): TAtlasCrumbActions;
begin
  Result := [TAtlasCrumbAction.CopyPath];
  if ACrumb.Badge.Kind = TAtlasBadgeKind.Unit_ then
  begin
    Result := Result + [TAtlasCrumbAction.CopyUnitName, TAtlasCrumbAction.CopyFilePath];
    Exit;
  end;
  if not ValidNode(ANodes, ACrumb.Node) or TAtlasOutline.IsSection(ANodes[ACrumb.Node]) then
  begin
    Exit;
  end;
  Result := Result + [TAtlasCrumbAction.CopyName, TAtlasCrumbAction.CopyWithUnit,
    TAtlasCrumbAction.FindReferences, TAtlasCrumbAction.Rename];
  if IsRoutine(ANodes[ACrumb.Node]) then
  begin
    Include(Result, TAtlasCrumbAction.CopySignature);
  end;
  if AHasComponent then
  begin
    Include(Result, TAtlasCrumbAction.ShowComponent);
  end;
end;

class function TAtlasCrumbMenu.NameOf(const ANodes: TAtlasOutlineNodes; ANode: Integer): string;
begin
  Result := TAtlasBreadcrumbs.QualifiedName(ANodes, ANode);
end;

/// <summary>AChar an AText anhängen; Leerraum zählt einmal als Leerzeichen, nur zwischen Zeichen.</summary>
procedure AddCollapsed(var AText: string; var ASpace: Boolean; AChar: Char);
begin
  if CharInSet(AChar, [' ', #9]) then
  begin
    ASpace := True;
    Exit;
  end;
  if ASpace and (AText <> '') then
  begin
    AText := AText + ' ';
  end;
  ASpace := False;
  AText := AText + AChar;
end;

/// <summary>Text ab ALine/ACharacter bis vor das erste Semikolon außerhalb von Klammern; Leerraum
/// zusammengezogen.</summary>
function HeaderFrom(const ALines: TArray<string>; ALine, ACharacter: Integer): string;
var
  mLine, mIndex, mDepth: Integer;
  mChar: Char;
  mSpace: Boolean;
begin
  Result := '';
  mDepth := 0;
  mSpace := False;
  for mLine := ALine to High(ALines) do
  begin
    mIndex := 1;
    if mLine = ALine then
    begin
      mIndex := ACharacter + 1;
    end;
    while mIndex <= Length(ALines[mLine]) do
    begin
      mChar := ALines[mLine][mIndex];
      case mChar of
        '(':
          Inc(mDepth);
        ')':
          Dec(mDepth);
        ';':
          if mDepth <= 0 then
          begin
            Exit(Trim(Result));
          end;
      end;
      AddCollapsed(Result, mSpace, mChar);
      Inc(mIndex);
    end;
    // Zeilenende zählt als Leerraum.
    mSpace := True;
  end;
  Result := Trim(Result);
end;

/// <summary>Erstes Zeichen der Zeile ohne Leerraum davor, 0-basiert.</summary>
function FirstCharacter(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and CharInSet(ALine[Result + 1], [' ', #9]) do
  begin
    Inc(Result);
  end;
end;

class function TAtlasCrumbMenu.SignatureOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  ANode: Integer): string;
var
  mTarget: Integer;
  mNode: TAtlasOutlineNode;
  mLine, mHead: string;
begin
  Result := '';
  if not ValidNode(ANodes, ANode) or not IsRoutine(ANodes[ANode]) then
  begin
    Exit;
  end;
  // Der Rumpf trägt den Besitzer schon im Kopf.
  mTarget := TAtlasBreadcrumbs.Target(ANodes, ANode, True);
  mNode := ANodes[mTarget];
  if (mNode.NameLine < 0) or (mNode.NameLine > High(ALines)) then
  begin
    Exit;
  end;
  mLine := ALines[mNode.NameLine];
  if Pos('.', mNode.Name) > 0 then
  begin
    Exit(HeaderFrom(ALines, mNode.NameLine, FirstCharacter(mLine)));
  end;
  // Deklaration ohne Rumpf: Wörter vor dem Namen, dann der Name mit Besitzer, dann der Rest.
  mHead := Trim(Copy(mLine, FirstCharacter(mLine) + 1, mNode.NameCharacter - FirstCharacter(mLine)));
  Result := HeaderFrom(ALines, mNode.NameLine, mNode.NameCharacter + Length(TAtlasBreadcrumbs.ShortName(mNode.Name)));
  Result := NameOf(ANodes, mTarget) + Result;
  if mHead <> '' then
  begin
    Result := mHead + ' ' + Result;
  end;
end;

class function TAtlasCrumbMenu.PathOf(const ACrumbs: TAtlasCrumbs): string;
var
  mCrumb: TAtlasCrumb;
begin
  Result := '';
  for mCrumb in ACrumbs do
  begin
    if Result <> '' then
    begin
      Result := Result + ' › ';
    end;
    Result := Result + mCrumb.Text;
  end;
end;

class function TAtlasCrumbMenu.MemberOf(const ANodes: TAtlasOutlineNodes; ANode: Integer): string;
var
  mNode: TAtlasOutlineNode;
begin
  Result := '';
  if not ValidNode(ANodes, ANode) then
  begin
    Exit;
  end;
  mNode := ANodes[ANode];
  if not (mNode.Category in [TAtlasOutlineCategory.Field, TAtlasOutlineCategory.Method]) then
  begin
    Exit;
  end;
  if ValidNode(ANodes, mNode.Parent) and (ANodes[mNode.Parent].Category = TAtlasOutlineCategory.TypeDecl) then
  begin
    Result := TAtlasBreadcrumbs.ShortName(mNode.Name);
  end;
end;

/// <summary>Zeile „Name = Wert“: Name und Wert ohne Leerraum; False sonst.</summary>
function Assignment(const ALine: string; out AName, AValue: string): Boolean;
var
  mEqual: Integer;
begin
  mEqual := Pos('=', ALine);
  Result := mEqual > 1;
  if Result then
  begin
    AName := Trim(Copy(ALine, 1, mEqual - 1));
    AValue := Trim(Copy(ALine, mEqual + 1, MaxInt));
  end;
end;

class function TAtlasCrumbMenu.ComponentOf(const AFormText, AMember: string): string;
var
  mLine, mName, mProperty, mValue, mTrimmed: string;
  mIsObject: Boolean;
  mStack: TArray<string>;
begin
  Result := '';
  if AMember = '' then
  begin
    Exit;
  end;
  mStack := nil;
  for mLine in AFormText.Split([#13#10, #10]) do
  begin
    mName := TAtlasFormChanges.ObjectName(mLine, mIsObject);
    mTrimmed := Trim(mLine);
    if mIsObject then
    begin
      if SameText(mName, AMember) then
      begin
        Exit(mName);
      end;
      mStack := mStack + [mName];
    end
    else if SameText(mTrimmed, 'item') then
    begin
      mStack := mStack + [''];
    end
    else if (SameText(mTrimmed, 'end') or SameText(mTrimmed, 'end>')) and (Length(mStack) > 0) then
    begin
      SetLength(mStack, Length(mStack) - 1);
    end
    else if (Length(mStack) > 0) and (mStack[High(mStack)] <> '') and Assignment(mTrimmed, mProperty, mValue) and
      mProperty.StartsWith('On', True) and SameText(mValue, AMember) then
    begin
      Exit(mStack[High(mStack)]);
    end;
  end;
end;

end.
