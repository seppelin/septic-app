use dioxus_router::prelude::{
    Outlet,
    Routable,
    Router,
};
use freya::prelude::*;
use crate::gob::Gob;

#[component]
pub fn App() -> Element {
    rsx!(Router::<Route> {})
}

#[derive(Routable, Clone, PartialEq)]
#[rustfmt::skip]
pub enum Route {
    #[layout(AppSidebar)]
        #[route("/")]
        Home,
        #[route("/gob")]
        Gob,
        #[route("/crab")]
        Crab,
    #[end_layout]
    #[route("/..route")]
    PageNotFound { },
}

#[component]
fn FromRouteToCurrent(from: Element, upwards: bool) -> Element {
    let mut animated_router = use_animated_router::<Route>();
    let (reference, node_size) = use_node();
    let animations = use_animation_with_dependencies(&upwards, move |ctx, upwards| {
        let (start, end) = if upwards { (1., 0.) } else { (0., 1.) };
        ctx.with(
            AnimNum::new(start, end)
                .time(300)
                .ease(Ease::InOut)
                .function(Function::Expo),
        )
    });

    // Only render the destination route once the animation has finished
    use_memo(move || {
        if !animations.is_running() && animations.has_run_yet() {
            animated_router.write().settle();
        }
    });

    // Run the animation when any prop changes
    use_memo(use_reactive((&upwards, &from), move |_| {
        animations.run(AnimDirection::Forward)
    }));

    let offset = animations.get().read().as_f32();
    let height = node_size.area.height();
    if height == 0.0 {
        return rsx!(
            rect {
                reference,
                height: "fill",
                width: "fill",
                Expand { {from} }
            }
        );
    }

    let offset = height - (offset * height);
    let to = rsx!(Outlet::<Route> {});
    let (top, bottom) = if upwards { (from, to) } else { (to, from) };

    rsx!(
        rect {
            reference,
            height: "fill",
            width: "fill",
            offset_y: "-{offset}",
            Expand { {top} }
            Expand { {bottom} }
        }
    )
}

#[component]
fn Expand(children: Element) -> Element {
    rsx!(
        rect {
            height: "100%",
            width: "100%",
            main_align: "center",
            cross_align: "center",
            {children}
        }
    )
}

#[component]
fn AnimatedOutlet(children: Element) -> Element {
    let animated_router = use_context::<Signal<AnimatedRouterContext<Route>>>();

    let from_route = match animated_router() {
        AnimatedRouterContext::FromTo(Route::Home, Route::Gob) => Some((rsx!(Home {}), true)),
        AnimatedRouterContext::FromTo(Route::Home, Route::Crab) => Some((rsx!(Home {}), true)),
        AnimatedRouterContext::FromTo(Route::Gob, Route::Home) => Some((rsx!(Gob {}), false)),
        AnimatedRouterContext::FromTo(Route::Gob, Route::Crab) => Some((rsx!(Gob {}), true)),
        AnimatedRouterContext::FromTo(Route::Crab, Route::Home) => Some((rsx!(Crab {}), false)),
        AnimatedRouterContext::FromTo(Route::Crab, Route::Gob) => Some((rsx!(Crab {}), false)),
        _ => None,
    };

    if let Some((from, upwards)) = from_route {
        rsx!(FromRouteToCurrent { upwards, from })
    } else {
        rsx!(
            Expand {
                Outlet::<Route> {}
            }
        )
    }
}

#[allow(non_snake_case)]
fn AppSidebar() -> Element {
    rsx!(
        NativeRouter {
            AnimatedRouter::<Route> {
                Sidebar {
                    sidebar: rsx!(
                        Link {
                            to: Route::Home,
                            ActivableRoute {
                                route: Route::Home,
                                exact: true,
                                SidebarItem {
                                    label {
                                        "Home"
                                    }
                                },
                            }
                        },
                        Link {
                            to: Route::Gob,
                            ActivableRoute {
                                route: Route::Gob,
                                SidebarItem {
                                    label {
                                        "Gob"
                                    }
                                },
                            }
                        },
                        Link {
                            to: Route::Crab,
                            ActivableRoute {
                                route: Route::Crab,
                                SidebarItem {
                                    label {
                                        "Go to Crab! 🦀"
                                    }
                                },
                            }
                        },
                    ),
                    Body {
                        AnimatedOutlet { }
                    }
                }
            }
        }
    )
}

#[allow(non_snake_case)]
#[component]
fn Home() -> Element {
    rsx!(
        label {
            "Just some text 😗 in /"
        }
    )
}

#[allow(non_snake_case)]
#[component]
fn Crab() -> Element {
    rsx!(
        label {
            "🦀🦀🦀🦀🦀 /crab"
        }
    )
}

#[allow(non_snake_case)]
#[component]
fn PageNotFound() -> Element {
    rsx!(
        label {
            "404!! 😵"
        }
    )
}