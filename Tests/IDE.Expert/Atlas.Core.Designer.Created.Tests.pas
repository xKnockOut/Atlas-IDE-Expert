unit Atlas.Core.Designer.Created.Tests;

// Tests für die angelegten Komponenten eines Designer-Werkzeugs und ihr
// Rückgängig (TAtlasDesignerCreated) gegen die Fälschung des Designers
// (TAtlasDesignSurfaceFake): Löschen rückwärts, vom Benutzer gelöschte,
// umbenannte und neu unter gleichem Namen angelegte Komponenten, Container
// mit Kindern, geschlossenes und anderes Formular, Löschen verweigert.
// Mit einem TDataModule als Formular, damit die Tests auch unter FPC laufen.

interface

uses
  System.Classes,
  System.TypInfo,
  DUnitX.TestFramework,
  Atlas.Core.Designer.Surface,
  Atlas.Core.Designer.Created,
  Atlas.Tests.DesignSurfaceFake;

type
  /// <summary>Komponente ohne VCL; ein Owner-Kind steht für ein Kind im Container.</summary>
  TAtlasCreatedWidget = class(TComponent);

  /// <summary>Reicht an die Fälschung weiter und merkt die Schlüssel, die gelöscht werden sollen.</summary>
  TAtlasCreatedDeleteLog = class(TInterfacedObject, IAtlasDesignSurface)
  private
    FInner: IAtlasDesignSurface;
    FKeys: TStringList;
  public
    constructor Create(const AInner: IAtlasDesignSurface);
    destructor Destroy; override;
    function Root: TComponent;
    procedure Modified;
    function DeleteComponent(const AKey: string): Boolean;
    function CreateComponent(AClass: TComponentClass; AParent: TComponent): TComponent;
    function MethodExists(const AName: string): Boolean;
    function CreateMethod(const AName: string; ATypeData: PTypeData): TMethod;
    function MethodName(const AMethod: TMethod): string;
    property Keys: TStringList read FKeys;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerCreatedTests = class
  private
    FFake: TAtlasDesignSurfaceFake;
    FSurface: IAtlasDesignSurface;
    FLog: TAtlasCreatedDeleteLog;
    FLogRef: IAtlasDesignSurface;
    FCreated: TAtlasDesignerCreated;
    /// <summary>Wie ein Werkzeug: über den Designer anlegen und merken.</summary>
    function CreateOne: TComponent;
    function Find(const AName: string): TComponent;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UndoDeletesInReverseOrder;
    [Test]
    procedure ComponentDeletedByUserIsSkipped;
    [Test]
    procedure RenamedComponentIsDeletedByNewName;
    [Test]
    procedure NewComponentUnderFreedNameSurvives;
    [Test]
    procedure ChildrenGoWithTheirContainer;
    [Test]
    procedure ClosedFormForgetsAll;
    [Test]
    procedure OtherFormIsNotTouched;
    [Test]
    procedure RefusedDeleteIsNotCounted;
    [Test]
    procedure ClearForgetsWithoutDeleting;
    [Test]
    procedure KeyFollowsOwners;
    [Test]
    procedure FreedBeforeComponents;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasCreatedDeleteLog }

constructor TAtlasCreatedDeleteLog.Create(const AInner: IAtlasDesignSurface);
begin
  inherited Create;
  FInner := AInner;
  FKeys := TStringList.Create;
end;

destructor TAtlasCreatedDeleteLog.Destroy;
begin
  FKeys.Free;
  inherited Destroy;
end;

function TAtlasCreatedDeleteLog.Root: TComponent;
begin
  Result := FInner.Root;
end;

procedure TAtlasCreatedDeleteLog.Modified;
begin
  FInner.Modified;
end;

function TAtlasCreatedDeleteLog.DeleteComponent(const AKey: string): Boolean;
begin
  FKeys.Add(AKey);
  Result := FInner.DeleteComponent(AKey);
end;

function TAtlasCreatedDeleteLog.CreateComponent(AClass: TComponentClass; AParent: TComponent): TComponent;
begin
  Result := FInner.CreateComponent(AClass, AParent);
end;

function TAtlasCreatedDeleteLog.MethodExists(const AName: string): Boolean;
begin
  Result := FInner.MethodExists(AName);
end;

function TAtlasCreatedDeleteLog.CreateMethod(const AName: string; ATypeData: PTypeData): TMethod;
begin
  Result := FInner.CreateMethod(AName, ATypeData);
end;

function TAtlasCreatedDeleteLog.MethodName(const AMethod: TMethod): string;
begin
  Result := FInner.MethodName(AMethod);
end;

{ TAtlasDesignerCreatedTests }

procedure TAtlasDesignerCreatedTests.Setup;
var
  mRoot: TDataModule;
begin
  mRoot := TDataModule.CreateNew(nil);
  mRoot.Name := 'Form1';
  FFake := TAtlasDesignSurfaceFake.Create(mRoot);
  FSurface := FFake;
  FLog := TAtlasCreatedDeleteLog.Create(FSurface);
  FLogRef := FLog;
  FCreated := TAtlasDesignerCreated.Create(nil);
end;

procedure TAtlasDesignerCreatedTests.TearDown;
begin
  FreeAndNil(FCreated);
  FLog := nil;
  FLogRef := nil;
  FFake := nil;
  FSurface := nil;
end;

function TAtlasDesignerCreatedTests.CreateOne: TComponent;
begin
  Result := FSurface.CreateComponent(TAtlasCreatedWidget, nil);
  FCreated.Add(Result);
end;

function TAtlasDesignerCreatedTests.Find(const AName: string): TComponent;
begin
  Result := FSurface.Root.FindComponent(AName);
end;

procedure TAtlasDesignerCreatedTests.UndoDeletesInReverseOrder;
begin
  FFake.Insert(TAtlasCreatedWidget, nil, 'Vorher');
  CreateOne;
  CreateOne;
  Assert.AreEqual(2, FCreated.Count);
  Assert.IsTrue(FCreated.Holds(FSurface));
  Assert.AreEqual(2, FCreated.Undo(FLogRef));
  Assert.AreEqual('AtlasCreatedWidget2,AtlasCreatedWidget1', FLog.Keys.CommaText);
  Assert.IsNull(Find('AtlasCreatedWidget1'));
  Assert.IsNull(Find('AtlasCreatedWidget2'));
  Assert.IsNotNull(Find('Vorher'), 'nicht angelegt, bleibt');
  Assert.AreEqual(0, FCreated.Count);
  Assert.IsFalse(FCreated.Holds(FSurface));
end;

procedure TAtlasDesignerCreatedTests.ComponentDeletedByUserIsSkipped;
begin
  CreateOne;
  FFake.Delete(CreateOne);
  Assert.AreEqual(1, FCreated.Count);
  Assert.AreEqual(1, FCreated.Undo(FLogRef));
  Assert.AreEqual('AtlasCreatedWidget1', FLog.Keys.CommaText);
end;

procedure TAtlasDesignerCreatedTests.RenamedComponentIsDeletedByNewName;
var
  mWidget: TComponent;
begin
  mWidget := CreateOne;
  FFake.Change(
    procedure
    begin
      mWidget.Name := 'Umbenannt';
    end);
  Assert.AreEqual(1, FCreated.Undo(FLogRef));
  Assert.AreEqual('Umbenannt', FLog.Keys.CommaText);
  Assert.IsNull(Find('Umbenannt'));
end;

procedure TAtlasDesignerCreatedTests.NewComponentUnderFreedNameSurvives;
begin
  FFake.Delete(CreateOne);
  FFake.Insert(TAtlasCreatedWidget, nil, 'AtlasCreatedWidget1');
  Assert.IsFalse(FCreated.Holds(FSurface));
  Assert.AreEqual(0, FCreated.Undo(FLogRef));
  Assert.AreEqual(0, FLog.Keys.Count);
  Assert.IsNotNull(Find('AtlasCreatedWidget1'), 'gehört dem Benutzer');
end;

procedure TAtlasDesignerCreatedTests.ChildrenGoWithTheirContainer;
var
  mContainer: TComponent;
begin
  mContainer := CreateOne;
  // Kinder hängen am Container: Freigabe des Containers nimmt sie mit, wie Steuerelemente im Parent.
  FCreated.Add(TAtlasCreatedWidget.Create(mContainer));
  FCreated.Add(TAtlasCreatedWidget.Create(mContainer));
  mContainer.Components[0].Name := 'Kind1';
  mContainer.Components[1].Name := 'Kind2';
  FFake.Delete(mContainer);
  Assert.AreEqual(0, FCreated.Count, 'Kinder mit dem Container freigegeben');
  Assert.AreEqual(0, FCreated.Undo(FLogRef));
end;

procedure TAtlasDesignerCreatedTests.ClosedFormForgetsAll;
begin
  CreateOne;
  CreateOne;
  FFake.Close;
  Assert.AreEqual(0, FCreated.Count);
  Assert.IsFalse(FCreated.Holds(FSurface));
  Assert.AreEqual(0, FCreated.Undo(FLogRef));
  Assert.AreEqual(0, FLog.Keys.Count);
end;

procedure TAtlasDesignerCreatedTests.OtherFormIsNotTouched;
var
  mOtherRoot: TDataModule;
  mOther: IAtlasDesignSurface;
begin
  CreateOne;
  mOtherRoot := TDataModule.CreateNew(nil);
  mOtherRoot.Name := 'Form2';
  mOther := TAtlasDesignSurfaceFake.Create(mOtherRoot);
  mOther.CreateComponent(TAtlasCreatedWidget, nil);
  Assert.IsFalse(FCreated.Holds(mOther));
  Assert.AreEqual(0, FCreated.Undo(mOther));
  Assert.IsNotNull(mOther.Root.FindComponent('AtlasCreatedWidget1'), 'gleicher Name im anderen Formular bleibt');
  Assert.AreEqual(1, FCreated.Count, 'Rückgängig bleibt fürs eigene Formular');
  Assert.AreEqual(1, FCreated.Undo(FLogRef));
end;

procedure TAtlasDesignerCreatedTests.RefusedDeleteIsNotCounted;
begin
  CreateOne;
  CreateOne;
  FFake.RefuseDelete('AtlasCreatedWidget1');
  Assert.AreEqual(1, FCreated.Undo(FLogRef));
  Assert.AreEqual('AtlasCreatedWidget2,AtlasCreatedWidget1', FLog.Keys.CommaText);
  Assert.IsNotNull(Find('AtlasCreatedWidget1'));
  Assert.AreEqual(0, FCreated.Count, 'danach nichts mehr gemerkt');
end;

procedure TAtlasDesignerCreatedTests.ClearForgetsWithoutDeleting;
var
  mWidget: TComponent;
begin
  mWidget := CreateOne;
  FCreated.Clear;
  Assert.AreEqual(0, FCreated.Count);
  Assert.AreEqual(0, FCreated.Undo(FLogRef));
  Assert.AreSame(mWidget, Find('AtlasCreatedWidget1'));
  // Ohne Abmeldung bei der Komponente schlüge die Freigabe hier in die Liste durch.
  FFake.Delete(mWidget);
  Assert.AreEqual(0, FCreated.Count);
end;

procedure TAtlasDesignerCreatedTests.KeyFollowsOwners;
var
  mFrame, mInner: TComponent;
begin
  mFrame := FFake.Insert(TAtlasCreatedWidget, nil, 'Frame1');
  mInner := TAtlasCreatedWidget.Create(mFrame);
  mInner.Name := 'Button1';
  Assert.AreEqual('Frame1.Button1', TAtlasDesignerCreated.KeyOf(FSurface.Root, mInner));
  Assert.AreEqual('Frame1', TAtlasDesignerCreated.KeyOf(FSurface.Root, mFrame));
  Assert.AreEqual('', TAtlasDesignerCreated.KeyOf(FSurface.Root, FSurface.Root));
  Assert.AreEqual('', TAtlasDesignerCreated.KeyOf(FSurface.Root, nil));
  Assert.AreEqual('', TAtlasDesignerCreated.KeyOf(mFrame, FSurface.Root), 'nicht darunter');
  mInner.Name := '';
  Assert.AreEqual('', TAtlasDesignerCreated.KeyOf(FSurface.Root, mInner), 'ohne Namen');
end;

procedure TAtlasDesignerCreatedTests.FreedBeforeComponents;
var
  mWidget: TComponent;
begin
  mWidget := CreateOne;
  FreeAndNil(FCreated);
  // Die Komponente darf nach dem Werkzeug keine Benachrichtigung mehr an es schicken.
  FFake.Delete(mWidget);
  Assert.IsNull(Find('AtlasCreatedWidget1'));
end;

end.
