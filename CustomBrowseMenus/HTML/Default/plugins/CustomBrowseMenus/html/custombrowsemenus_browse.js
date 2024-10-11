CBMBrowse = {
		init : function(){
			var el;

			// jump to anchor
			var anchor = location.hash.replace(/#/,'');
			if (anchor) {
				if (el = Ext.get('anchor' + anchor))
					el.scrollIntoView('browsedbList');
			}

			// Album view selector
			if (Ext.get('viewSelect')) {
				var viewMode = (SqueezeJS.getCookie('LMS-albumView') && SqueezeJS.getCookie('LMS-albumView').match(/[012]/) ? SqueezeJS.getCookie('LMS-albumView') : '0');
				var menu;
				if (artworkList==1) {
					menu = new Ext.menu.Menu({
						items: [
							new Ext.menu.CheckItem({
								text: SqueezeJS.string('switch_to_list'),
								cls: 'albumList',
								handler: function(){ CBMBrowse.toggleGalleryView(2) },
								group: 'viewMode',
								checked: viewMode == 2
							}),
							new Ext.menu.CheckItem({
								text: SqueezeJS.string('switch_to_extended_list'),
								cls: 'albumXList',
								handler: function(){ CBMBrowse.toggleGalleryView(0) },
								group: 'viewMode',
								checked: viewMode == 0
							}),
							new Ext.menu.CheckItem({
								text: SqueezeJS.string('switch_to_gallery'),
								cls: 'albumListGallery',
								handler: function(){ CBMBrowse.toggleGalleryView(1) },
								group: 'viewMode',
								checked: viewMode == 1
							})
						]
					});
				} else {
					menu = new Ext.menu.Menu({
						items: []
					});
				}


				if (orderByList) {
					menu.add(
							'-',
							'<span class="menu-title">' + SqueezeJS.string('sort_by') + '...</span>'
					);

					var sortOrder = SqueezeJS.getCookie('LMS-CustomBrowseMenus-option');
					for (order in orderByList) {
						menu.add(new Ext.menu.CheckItem({
							text: order,
							handler: function(ev){
								CBMBrowse.chooseAlbumOrderBy(orderByList[ev.text]);
							},
							checked: (orderByList[order] == sortOrder),
							group: 'sortOrder'
						}));
					}
				}


				new Ext.SplitButton({
					renderTo: 'viewSelect',
					icon: webroot + 'html/images/albumlist' + viewMode + '.gif',
					cls: 'x-btn-icon',
					menu: menu,
					handler: function(ev){
						if (this.menu && !this.menu.isVisible()){
							this.menu.show(this.el, this.menuAlign);
						}
						this.fireEvent('arrowclick', this, ev);
					},
					tooltip: SqueezeJS.string('display_options'),
					arrowTooltip: SqueezeJS.string('display_options'),
					tooltipType: 'title'
				});
			}
		},

		gotoAnchor : function(anchor){
			var el = Ext.get('anchor' + anchor);
			if (el)
				el.scrollIntoView('browsedbList');
		},

		toggleGalleryView : function(artwork){
			var params = location.search;
			params = params.replace(/&artwork=\w*/gi, '');

			if (artwork == 1) {
				SqueezeJS.setCookie( 'LMS-albumView', "1" );
				params += '&artwork=1';
			}

			else if (artwork == 2) {
				SqueezeJS.setCookie( 'LMS-albumView', "2" );
				params += '&artwork=2';
			}

			else {
				SqueezeJS.setCookie( 'LMS-albumView', "" );
				params += '&artwork=0';
			}

			location.search = params;
		},

		chooseAlbumOrderBy: function(option) {
			var params = location.search;
			params = params.replace(/&option=[\w\.,]*/ig, '');

			if (option)
				params += '&option=' + option;

			SqueezeJS.setCookie('LMS-CustomBrowseMenus-option', option);
			location.search = params;
		}

};

