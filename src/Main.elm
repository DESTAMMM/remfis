module Main exposing (main)

import Browser
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Color exposing (Color)
import TypedSvg as Svg
import TypedSvg.Attributes as Attributes
import TypedSvg.Core exposing (Svg)
import TypedSvg.Types exposing (px, Paint(..))
import Math.Vector2 as Vector2
import Draggable
import Draggable.Events
import Json.Decode as Json
import Element as E
import Element.Input as Input
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Events
import Html.Events.Extra.Mouse as Mouse
import Process
import Task


type alias Model =
  { fields : List Field
  , activeSourceId : Maybe Id
  , nextId : Id
  , drag : Draggable.State Id
  , contextMenu : ContextMenu
  , popUp: PopUp
  , settings : Settings
  , pendingSettings : Settings
  , isWheeling : Bool
  , isWheelingTimeOutCleared : Bool
  , width : Float
  , height : Float
  }


type alias Settings =
  { r : Float
  , density : Int
  , steps : Int
  , delta : Float
  , magnitude : Float
  }


type ContextMenu
  = FieldContextMenu
  | GeneralContextMenu Position
  | NoContextMenu


type PopUp
  = HelpPopUp
  | SettingsPopUp
  | ApplyOptionsPopUp
  | NoPopUp


type alias Field =
  { source: Charge
  , density: Int
  , steps: Int
  , delta: Float
  , lines: List Line
  }

type alias Id =
  Int

type alias Line =
  List Point

type alias Point =
  (Float, Float)

type alias Position =
  Point

type Sign
  = Positive
  | Negative

type alias Charge =
  { id : Id
  , sign: Sign
  , magnitude: Float
  , x: Float
  , y: Float
  , r: Float
  }


style :
  { button : List (E.Attribute Msg)
  }
style =
  { button =
    [ Background.color <| toElmUiColor Color.lightGrey
    , E.mouseOver
        [ Background.color <| toElmUiColor Color.grey ]
    , E.paddingXY 10 5
    , E.width <| E.px 150
    , Border.widthXY 2 1
    , Border.color <| toElmUiColor Color.darkGrey
    ]
  }


initialModel : () -> (Model, Cmd Msg)
initialModel _ =
  let
    fields =
      [{ source = { id = 0, sign = Negative, magnitude = 3.0, x = 465.0, y = 270.0, r = 10.0 }
      , density = 30
      , steps = 900
      , delta = 1
      , lines = []
      }
      , { source = { id = 1, sign = Positive, magnitude = 1.0, x = 618.0, y = 515.0, r = 10.0 }
      , density = 30
      , steps = 900
      , delta = 1
      , lines = []
      }
      , { source = { id = 2, sign = Positive, magnitude = 10.0, x = 553.0, y = 338.0, r = 10.0 }
      , density = 30
      , steps = 900
      , delta = 1
      , lines = []
      }
      , { source = { id = 3, sign = Negative, magnitude = 20.0, x = 597.0, y = 182.0, r = 10.0 }
      , density = 30
      , steps = 900
      , delta = 1
      , lines = []
      }
      ]
    defaultSettings =
      { r = 10.0
      , density = 30
      , steps = 900
      , delta = 1
      , magnitude = 1.0
      }
    width = 1200
    height = 780
  in
  ({ fields =
    calculateFields width height fields
  , activeSourceId = if List.length fields > 0 then Just 0 else Nothing
  , nextId = List.length fields
  , drag = Draggable.init
  , contextMenu = NoContextMenu
  , popUp = NoPopUp
  , settings = defaultSettings
  , pendingSettings = defaultSettings
  , isWheeling = False
  , isWheelingTimeOutCleared = False
  , width = width
  , height = height
  }
  , Cmd.none
  )


calculateFields : Float -> Float -> List Field -> List Field
calculateFields width height fields =
  List.map
    (\field ->
      let
        deltaAngle =
          2 * pi / toFloat field.density
        lines =
          List.map
            (\index ->
              let
                angle =
                  deltaAngle * index
                x =
                  field.source.x + field.source.r * cos angle
                y =
                  field.source.y + field.source.r * sin angle
              in
              calculateFieldLine
                { charges = List.map .source fields
                , steps = field.steps
                , delta = field.delta
                , sourceSign = field.source.sign
                , start = (x, y)
                , xBound = width
                , yBound = height
                }
            )
            (List.map toFloat <| List.range 0 (field.density - 1))
      in
      { field |
        lines = lines
      }
    )
    fields


calculateFieldLine :
  { charges : List Charge
  , steps : Int
  , delta : Float
  , sourceSign : Sign
  , start : Point
  , xBound : Float
  , yBound : Float
  } -> Line
calculateFieldLine { charges, steps, delta, sourceSign, start, xBound, yBound } =
  foldlWhile
    (\_ line ->
      let
        (x, y) =
          case line of
            prev :: _ ->
              prev
            _ ->
              (0, 0) -- impossible
        outOfBounds =
          x > xBound || x < 0 || y > yBound || y < 0
        netField =
          if outOfBounds then
            Vector2.vec2 0 0
          else
            List.foldl
            (\charge sum ->
              let
                d =
                  distance (x, y) (charge.x, charge.y) / 100
                magnitude =
                  charge.magnitude / (d ^ 2)
                sign =
                  case charge.sign of
                    Positive ->
                      1
                    Negative ->
                      -1
                field =
                  Vector2.scale (sign * magnitude) <|
                    Vector2.normalize <|
                      Vector2.vec2 (x - charge.x) (y - charge.y)
              in
              Vector2.add sum field
            )
            (Vector2.vec2 0 0)
            charges
        next =
          if outOfBounds then
            (x, y)
          else
            let
              vec =
                Vector2.add
                  (Vector2.vec2 x y)
                  ((case sourceSign of
                    Positive ->
                      identity
                    Negative ->
                      Vector2.negate
                  )<|
                    Vector2.scale delta <|
                      Vector2.normalize netField
                  )
            in
            (Vector2.getX vec, Vector2.getY vec)
      in
      (next :: line, outOfBounds)
  )
  [ start ]
  (List.range 0 (steps - 1))


distance : Point -> Point -> Float
distance (x1, y1) (x2, y2) =
  sqrt ((x2 - x1) ^ 2 + (y2 - y1) ^ 2)


type Msg
  = OnDragBy Draggable.Delta
  | DragMsg (Draggable.Msg Id)
  | StartDragging Id
  | EndDragging
  | ActivateSource Id
  | ToggleSourceSign
  | ScaleSourceMagnitude Int
  | ShowFieldContextMenu
  | ShowGeneralContextMenu Mouse.Event
  | DeleteActiveField
  | ClickedBackground
  | DuplicateActiveField
  | DeselectActiveField
  | AddPositiveCharge Position
  | AddNegativeCharge Position
  | ShowPopUp PopUp
  | UpdatePendingSetting String String
  | ApplyPendingSettings
  | ApplySettingsToFutureFields
  | ApplySettingsToCurrentAndFutureFields
  | CloseSettingsPopUp
  | CloseHelpPopUp
  | StopWheelingTimeOut
  | DoNothing


dragConfig : Draggable.Config Id Msg
dragConfig =
  Draggable.customConfig
    [ Draggable.Events.onDragBy OnDragBy
    , Draggable.Events.onDragStart StartDragging
    , Draggable.Events.onDragEnd EndDragging
    , Draggable.Events.onClick ActivateSource
    ]


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    OnDragBy offsetPos ->
      (onDragBy offsetPos model, Cmd.none)

    StartDragging id ->
      (startDragging id model, Cmd.none)

    EndDragging ->
      (endDragging model, Cmd.none)

    ActivateSource id ->
      (setActiveSourceId id model, Cmd.none)

    ToggleSourceSign ->
      (toggleSourceSign model, Cmd.none)

    ScaleSourceMagnitude delta ->
      scaleSourceMagnitude delta model

    StopWheelingTimeOut ->
      (stopWheelingTimeOut model, Cmd.none)

    DragMsg dragMsg ->
      Draggable.update dragConfig dragMsg model

    ShowFieldContextMenu ->
      (showFieldContextMenu model, Cmd.none)

    ShowGeneralContextMenu { offsetPos } ->
      (showGeneralContextMenu offsetPos model, Cmd.none)

    DeleteActiveField ->
      (deleteActiveField model, Cmd.none)

    ClickedBackground ->
      (resetState model, Cmd.none)

    DuplicateActiveField ->
      (duplicateActiveField model, Cmd.none)

    DeselectActiveField ->
      (deselectActiveField model, Cmd.none)

    AddPositiveCharge position ->
      (addCharge Positive position model, Cmd.none)

    AddNegativeCharge position ->
      (addCharge Negative position model, Cmd.none)

    ShowPopUp popUp ->
      (showPopUp popUp model, Cmd.none)

    UpdatePendingSetting field value ->
      (updatePendingSetting field value model, Cmd.none)

    ApplyPendingSettings ->
      (applyPendingSettings model, Cmd.none)

    ApplySettingsToFutureFields ->
      (applySettingsToFutureFields model, Cmd.none)

    ApplySettingsToCurrentAndFutureFields ->
      (applySettingsToCurrentAndFutureFields model, Cmd.none)

    CloseSettingsPopUp ->
      (closeSettingsPopUp model, Cmd.none)

    CloseHelpPopUp ->
      (closeHelpPopUp model, Cmd.none)

    DoNothing ->
      (model, Cmd.none)


onDragBy : Position -> Model -> Model
onDragBy offsetPos model =
  let
    newFields =
      updateActive (dragSource offsetPos) model.activeSourceId model.fields
  in
  { model |
    fields =
      calculateFields model.width model.height newFields
  }


startDragging : Id -> Model -> Model
startDragging id model =
  setActiveSourceId id <| optimizeModel model


optimizeModel : Model -> Model
optimizeModel model =
  { model
    | fields =
      List.map
        (\field ->
          if field.delta <= 7 then
            { field
              | delta =
                field.delta * 3
              , steps =
                round <| toFloat field.steps / 3
            }
          else
            field
        )
        model.fields
  }


endDragging : Model -> Model
endDragging model =
  deoptimizeModel model


deoptimizeModel : Model -> Model
deoptimizeModel model =
  { model
    | fields =
      calculateFields model.width model.height <|
      List.map
        (\field ->
          if field.delta <= 7 then
            { field
              | delta =
                field.delta / 3
              , steps =
                field.steps * 3
            }
          else
            field
        )
        model.fields
  }


closeHelpPopUp : Model -> Model
closeHelpPopUp model =
  { model
    | popUp =
      NoPopUp
  }



closeSettingsPopUp : Model -> Model
closeSettingsPopUp model =
  { model
    | popUp =
      NoPopUp
    , pendingSettings =
      model.settings
  }


applyPendingSettings : Model -> Model
applyPendingSettings model =
  { model |
    popUp =
      ApplyOptionsPopUp
  }


applySettingsToFutureFields : Model -> Model
applySettingsToFutureFields model =
  { model
    | settings =
      model.pendingSettings
    , popUp =
      NoPopUp
  }


applySettingsToCurrentAndFutureFields : Model -> Model
applySettingsToCurrentAndFutureFields model =
  let
    newSettings =
      model.pendingSettings
    newFields =
      List.map
        (\field ->
          let
            source =
              field.source
          in
          { field
            | source =
              { source
                | r = newSettings.r
                , magnitude = newSettings.magnitude
              }
            , density =
              newSettings.density
            , steps =
              newSettings.steps
            , delta =
              newSettings.delta
          }
        )
        model.fields
  in
  { model
    | fields =
      calculateFields model.width model.height newFields
    , settings =
      newSettings
    , popUp =
      NoPopUp
  }


updatePendingSetting : String -> String -> Model -> Model
updatePendingSetting field value model =
  let
    settings =
      model.pendingSettings
    newSettings =
      case field of
        "r" ->
          case String.toFloat value of
            Just v -> { settings | r = v }
            Nothing -> settings
        "density" ->
          case String.toInt value of
            Just v -> { settings | density = v }
            Nothing -> settings
        "steps" ->
          case String.toInt value of
            Just v -> { settings | steps = v }
            Nothing -> settings
        "delta" ->
          case String.toFloat value of
            Just v -> { settings | delta = v }
            Nothing -> settings
        "magnitude" ->
          case String.toFloat value of
            Just v -> { settings | magnitude = v }
            Nothing -> settings
        _ ->
          settings
  in
  { model |
    pendingSettings =
      newSettings
  }


showPopUp : PopUp -> Model -> Model
showPopUp popUp model =
  { model |
    popUp =
      popUp
  }


setActiveSourceId : Id -> Model -> Model
setActiveSourceId id model =
  { model |
    activeSourceId = Just id
  }


toggleSourceSign : Model -> Model
toggleSourceSign model =
  let
    newFields =
      updateActive
        (\field ->
          let
            source =
              field.source
          in
          { field |
            source =
              { source |
                sign =
                  negateSign field.source.sign
              }
          }
        )
        model.activeSourceId
        model.fields
  in
  { model
    | fields =
      calculateFields model.width model.height newFields
  }


scaleSourceMagnitude : Int -> Model -> (Model, Cmd Msg)
scaleSourceMagnitude delta model =
  let
    newModel =
      if model.isWheeling then
        model
      else
        optimizeModel model
    newFields =
      updateActive
        (\field ->
          let
            source =
              field.source
          in
          { field |
            source =
              { source |
                magnitude =
                  min 20 <| max 0.5 <| source.magnitude + toFloat delta * -0.01
              }
          }
        )
        newModel.activeSourceId
        newModel.fields
  in
  ({ model
    | fields =
      calculateFields model.width model.height newFields
    , isWheeling =
      True
    , isWheelingTimeOutCleared =
      True
  }
  , setTimeOut 200 StopWheelingTimeOut
  )


setTimeOut : Float -> msg -> Cmd msg
setTimeOut time msg =
  Process.sleep time
  |> Task.perform (\_ -> msg)


stopWheelingTimeOut : Model -> Model
stopWheelingTimeOut model =
  if model.isWheelingTimeOutCleared then
    { model
      | isWheelingTimeOutCleared = False
    }
  else
    deoptimizeModel { model
      | isWheeling = False
      , isWheelingTimeOutCleared = False
    }


showFieldContextMenu : Model -> Model
showFieldContextMenu model =
  { model
    | contextMenu =
      case model.activeSourceId of
        Nothing ->
          model.contextMenu
        Just _ ->
          FieldContextMenu
  }


showGeneralContextMenu : Position -> Model -> Model
showGeneralContextMenu offsetPos model =
  { model |
    contextMenu =
      GeneralContextMenu offsetPos
  }


deleteActiveField : Model -> Model
deleteActiveField model =
  let
    newFields =
      case model.activeSourceId of
        Nothing ->
          model.fields
        Just id ->
          List.filter
            (\field ->
              field.source.id /= id
            )
            model.fields
  in
  { model |
    fields =
      calculateFields model.width model.height newFields
    , contextMenu =
      NoContextMenu
    , activeSourceId =
      Nothing
  }


addCharge : Sign -> Position -> Model -> Model
addCharge sign (x, y) model =
  let
    newCharge : Charge
    newCharge =
      { sign = sign
      , magnitude = model.settings.magnitude
      , x = x
      , y = y
      , r = model.settings.r
      , id = model.nextId
      }
    newField : Field
    newField =
      { source = newCharge
      , density = model.settings.density
      , steps = model.settings.steps
      , delta = model.settings.delta
      , lines = []
      }
    newFields : List Field
    newFields =
      newField :: model.fields
  in
  { model
    | fields =
      calculateFields model.width model.height newFields
    , nextId =
      model.nextId + 1
  }


duplicateActiveField : Model -> Model
duplicateActiveField model =
  let
    duplicatedFields =
      List.indexedMap
        (\index field ->
          let
            source =
              field.source
          in
          { field |
            source =
              { source
                | x =
                  source.x + source.r * 2 + 15
                , id =
                  model.nextId + index
              }
          }
        )
        (getActiveFields model)
    newFields =
      model.fields ++ duplicatedFields
  in
  { model
    | fields =
      calculateFields model.width model.height newFields
    , nextId =
      model.nextId + List.length duplicatedFields
  }


deselectActiveField : Model -> Model
deselectActiveField model =
  { model
    | activeSourceId =
      Nothing
  }


resetState : Model -> Model
resetState model =
  closeHelpPopUp <|
  closeSettingsPopUp <|
    { model
      | contextMenu =
        NoContextMenu
    }


updateActive : (Field -> Field) -> Maybe Id -> List Field -> List Field
updateActive func activeId fields =
  case activeId of
    Nothing ->
      fields
    Just id ->
      List.map
        (\field ->
          if field.source.id == id then
            func field
          else
            field
        )
        fields


dragSource : Position -> Field -> Field
dragSource (dx, dy) field =
  let
    source =
      field.source
  in
  { field |
    source =
      { source
        | x = field.source.x + dx
        , y = field.source.y + dy
      }
  }


view : Model -> Html Msg
view model =
  E.layout
    [ E.width E.fill
    , E.height E.fill
    , Element.Events.onClick ClickedBackground
    , E.htmlAttribute <| Mouse.onContextMenu ShowGeneralContextMenu
    , Font.size 16
    , Font.family
      [ Font.monospace
      ]
    ] <|
    E.el
      [ E.inFront <| viewContextMenu model
      , E.inFront <| viewPopUp model
      , E.below <| viewPopUpSelector
      , E.centerX
      , E.centerY
      ]
      ( E.html <| Svg.svg
        [ Attributes.width (px model.width)
        , Attributes.height (px model.height)
        , Attributes.viewBox 0 0 model.width model.height
        ] <|
        List.map viewFieldLines model.fields
        ++ List.map (viewFieldSource model.activeSourceId) model.fields
      )


viewPopUpSelector : E.Element Msg
viewPopUpSelector =
  E.row
    [ E.centerX
    , E.spacing 10
    ]
    [ viewButtonNoProp "Help" <| ShowPopUp HelpPopUp
    , viewButtonNoProp "Settings" <| ShowPopUp SettingsPopUp
    ]


viewButtonNoProp : String -> Msg -> E.Element Msg
viewButtonNoProp text msg =
  Input.button (style.button ++ [
    E.htmlAttribute <| onClickNoProp msg
  ]) <|
    { onPress =
      Nothing
    , label = centeredText text
    }


viewPopUp : Model -> E.Element Msg
viewPopUp model =
  case model.popUp of
    HelpPopUp ->
      viewHelpPopUp
    SettingsPopUp ->
      viewSettingsPopUp model
    ApplyOptionsPopUp ->
      viewApplyOptions model
    NoPopUp ->
      E.none


viewSettingsPopUp : Model -> E.Element Msg
viewSettingsPopUp model =
  let
    settings =
      model.pendingSettings
  in
  viewPopUpOf "Settings"
    [ E.inFront <| viewApplyOptions model
    ]
    [ Input.text []
      { onChange = UpdatePendingSetting "r"
       , text = String.fromFloat settings.r
       , placeholder = Nothing
       , label = Input.labelLeft [ E.centerY ] <| E.text "Charge radius (px)"
       }
    , Input.text []
      { onChange = UpdatePendingSetting "density"
       , text = String.fromInt settings.density
       , placeholder = Nothing
       , label = Input.labelLeft [ E.centerY ] <| E.text "Field line density"
       }
    , Input.text []
      { onChange = UpdatePendingSetting "steps"
      , text = String.fromInt settings.steps
      , placeholder = Nothing
      , label = Input.labelLeft [ E.centerY ] <| E.text "Draw steps"
      }
  , Input.text []
    { onChange = UpdatePendingSetting "delta"
    , text = String.fromFloat settings.delta
    , placeholder = Nothing
    , label = Input.labelLeft [ E.centerY ] <| E.text "Draw step size (px)"
    }
  , Input.text []
    { onChange = UpdatePendingSetting "magnitude"
    , text = String.fromFloat settings.magnitude
    , placeholder = Nothing
    , label = Input.labelLeft [ E.centerY ] <| E.text "Charge magnitude"
    }
  , E.row
    [ E.width E.fill
    , E.paddingEach
      { top = 20, right = 0, bottom = 0, left = 0 }
    ]
    [ Input.button (style.button ++ [E.alignLeft])
      { onPress =
        Just ApplyPendingSettings
      , label =
        centeredText "Apply"
      }
      , Input.button (style.button ++ [E.alignRight])
      { onPress =
        Just CloseSettingsPopUp
      , label =
        centeredText "Cancel"
      }
    ]
  ]


viewApplyOptions : Model -> E.Element Msg
viewApplyOptions model =
  case model.popUp of
    ApplyOptionsPopUp ->
      viewPopUpOf "Which fields do you want to apply to?" []
        [ Input.button
          (style.button ++ [ E.width <| E.fill ] )
          { onPress = Just ApplySettingsToFutureFields
          , label = centeredText "Apply to future fields"
          }
        , Input.button
          (style.button ++ [ E.width <| E.fill ] )
          { onPress = Just ApplySettingsToCurrentAndFutureFields
          , label = centeredText "Apply to current and future fields"
          }
        ]
    _ ->
      E.none


viewHelpPopUp : E.Element Msg
viewHelpPopUp =
  viewPopUpOf "Help" []
    [ textHeader "When you mouse over a charge and ..."
    , E.text "  Single click: select charge"
    , E.text "  Double click: negate charge"
    , E.text "  Right click:  * delete charge"
    , E.text "                * duplicate charge"
    , E.text "                * deselect charge"
    , E.text "  Scroll up:    increase charge magnitude"
    , E.text "  Scroll down:  decrease charge magnitude"
    , textHeader "When you mouse over background and ..."
    , E.text "  Right Click:  * add + charge"
    , E.text "                * add - charge"
    , E.el [ E.paddingEach { top = 20, right = 0, bottom = 0, left = 0 } ] <|
      Input.button
        style.button
        { onPress = Just CloseHelpPopUp
        , label = centeredText "Close"
        }
      ]


viewPopUpOf : String -> List (E.Attribute Msg) -> List (E.Element Msg) -> E.Element Msg
viewPopUpOf title attributes content =
  E.column
    ([ E.centerX
    , E.centerY
    , E.padding 20
    , E.spacing 6
    , Background.color <| toElmUiColor Color.lightGrey
    , Border.width 2
    , Border.color <| toElmUiColor Color.black
    , E.htmlAttribute <| onClickNoProp DoNothing
    ] ++ attributes) <|
    [ E.el
      [ Font.size 18
      , E.paddingEach
        { left = 0
        , right = 0
        , top = 0
        , bottom = 10
        }
      ] <|
      E.text title
    ] ++ content


textHeader : String -> E.Element Msg
textHeader text =
  E.el
    [ E.paddingXY 0 6
    ] <|
    E.text text


viewContextMenu : Model -> E.Element Msg
viewContextMenu model =
  case model.contextMenu of
    FieldContextMenu ->
      viewFieldContextMenu style.button model
    GeneralContextMenu position ->
      viewGeneralContextMenu style.button position
    NoContextMenu ->
      E.none


getActiveFields : Model -> List Field
getActiveFields model =
  case model.activeSourceId of
    Just id ->
      List.filter
        (\field ->
          field.source.id == id
        )
        model.fields
    Nothing ->
      []


viewFieldContextMenu : List (E.Attribute Msg) -> Model -> E.Element Msg
viewFieldContextMenu menuItemStyles model =
  let
    (x, y) =
      case List.head <| getActiveFields model of
        Just field ->
          (field.source.x, field.source.y)
        Nothing ->
          (0, 0) -- impossible
  in
  E.column
    [ E.moveRight x
    , E.moveDown y
    ]
    [ Input.button
      menuItemStyles
      { onPress = Just DeleteActiveField
      , label = E.text "Delete"
      }
    , Input.button
      menuItemStyles
      { onPress = Just DuplicateActiveField
      , label = E.text "Duplicate"
      }
    , Input.button
      menuItemStyles
      { onPress = Just DeselectActiveField
      , label = E.text "Deselect"
      }
    ]


viewGeneralContextMenu : List (E.Attribute Msg) -> Position -> E.Element Msg
viewGeneralContextMenu menuItemStyles (x, y) =
  E.column
    [ E.moveRight x
    , E.moveDown y
    ]
    [ Input.button
      menuItemStyles
      { onPress = Just <| AddPositiveCharge (x, y)
      , label = E.text "Add + charge"
      }
    , Input.button
      menuItemStyles
      { onPress = Just <| AddNegativeCharge (x, y)
      , label = E.text "Add - charge"
      }
    ]


viewFieldSource : Maybe Id -> Field -> Svg Msg
viewFieldSource activeSourceId field =
  let
    fill =
      signToColor field.source.sign
    gradientId =
      "gradient" ++ String.fromInt field.source.id
  in
  Svg.g []
  [ Svg.defs []
    [ Svg.radialGradient
      [ Attributes.id <| gradientId ]
      [ Svg.stop
        [ Attributes.offset "1%"
        , Attributes.stopColor <| Color.toCssString <| setAlpha 1 fill
        ] []
      , Svg.stop
        [ Attributes.offset "100%"
        , Attributes.stopColor <| Color.toCssString <| setAlpha 0.2 fill
        ] []
      ]
    ]
  , Svg.circle
    [ Attributes.cx (px field.source.x)
    , Attributes.cy (px field.source.y)
    , Attributes.r (px <| lerp 0 20 10 40 (min 20 field.source.r * field.source.magnitude / 10))
    , Attributes.fill <| Reference gradientId
    , Html.Attributes.style "pointer-events" "none"
    ]
    []
  , Svg.circle
    ([ Attributes.cx (px field.source.x)
    , Attributes.cy (px field.source.y)
    , Attributes.r (px field.source.r)
    , Attributes.fill <| Paint fill
    , Draggable.mouseTrigger field.source.id DragMsg
    , onWheel ScaleSourceMagnitude
    , Html.Events.onDoubleClick ToggleSourceSign
    , onRightClick ShowFieldContextMenu
    ] ++ Draggable.touchTriggers field.source.id DragMsg
    ++ case activeSourceId of
      Just id ->
        if field.source.id == id then
          [ Attributes.stroke <| Paint Color.lightGreen
          , Attributes.strokeWidth <| px 2.5
          ]
        else
          []
      Nothing ->
        []
    )
    [ Svg.animate
      [ Attributes.attributeName "stroke-opacity"
      , Attributes.animationValues [ 1, 0.3, 1 ]
      , Attributes.dur <| TypedSvg.Types.Duration "3s"
      , Attributes.repeatCount TypedSvg.Types.RepeatIndefinite
      ] []
    ]
  ]


viewFieldLines : Field -> Svg Msg
viewFieldLines field =
  Svg.g [] <|
    List.map
      (\line -> Svg.polyline
        [ Attributes.fill PaintNone, Attributes.stroke <| Paint Color.black, Attributes.points line ]
        []
      )
      field.lines


onWheel : (Int -> msg) -> Html.Attribute msg
onWheel message =
  Html.Events.on "wheel" (Json.map message (Json.at ["deltaY"] Json.int ))


onRightClick : msg -> Html.Attribute msg
onRightClick msg =
  Html.Events.custom "contextmenu"
    (Json.succeed
      { message = msg
      , stopPropagation = True
      , preventDefault = True
      }
    )


onClickNoProp : Msg -> Html.Attribute Msg
onClickNoProp msg =
  Html.Events.custom "click"
    (Json.succeed
    { message = msg
    , stopPropagation = True
    , preventDefault = False
    }
  )


signToColor : Sign -> Color
signToColor sign =
  case sign of
    Positive ->
      Color.orange
    Negative ->
      Color.blue


setAlpha : Float -> Color -> Color
setAlpha alpha color =
  let
    rgba =
      Color.toRgba color
  in
  Color.fromRgba <|
    { rgba |
      alpha = alpha
    }


negateSign : Sign -> Sign
negateSign sign =
  case sign of
    Positive ->
      Negative
    Negative ->
      Positive


centeredText : String -> E.Element Msg
centeredText text =
  E.el [ E.centerX ] <|
    E.text text


lerp : Float -> Float -> Float -> Float -> Float -> Float
lerp min1 max1 min2 max2 num =
  let
    ratio =
      abs <| (num - min1) / (max1 - min1)
  in
  min2 + ratio * (max2 - min2)


toElmUiColor : Color.Color -> E.Color
toElmUiColor color =
    let
        {red, green, blue, alpha } =
            Color.toRgba color
    in
    E.rgba red green blue alpha


foldlWhile : (a -> b -> (b, Bool)) -> b -> List a -> b
foldlWhile accumulate initial list =
  let
    foldlHelper accumulated aList =
      case aList of
        head :: tail ->
          let
            (nextAccumulated, break) = accumulate head accumulated
          in
          if break then
            nextAccumulated
          else
            foldlHelper nextAccumulated tail
        [] ->
          accumulated
  in
  foldlHelper initial list


subscriptions : Model -> Sub Msg
subscriptions { drag } =
  Draggable.subscriptions DragMsg drag


main : Program () Model Msg
main =
  Browser.element
    { init = initialModel
    , view = view
    , update = update
    , subscriptions = subscriptions
    }