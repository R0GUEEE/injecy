//
//  injecyWidgetsBundle.swift
//  injecyWidgets
//
//  Widget extension hosting the injecy Live Activity.
//

import SwiftUI
import WidgetKit

@main
struct injecyWidgetsBundle: WidgetBundle {
	var body: some Widget {
		if #available(iOS 16.2, *) {
			InjecyLiveActivity()
		}
	}
}
